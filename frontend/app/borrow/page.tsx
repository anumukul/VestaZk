"use client";

import { useState, useEffect } from "react";
import { useAccount } from "@starknet-react/core";
import { VaultClient } from "@/lib/vault-contract";
import { getCommitmentData } from "@/lib/commitment-storage";
import { generateBorrowProof } from "@/lib/noir-prover";
import { WalletConnect } from "@/components/WalletConnect";
import Link from "next/link";

export default function BorrowPage() {
  const { account, address } = useAccount();
  const [borrowAmount, setBorrowAmount] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);
  const [status, setStatus] = useState("");
  const [hasCommitment, setHasCommitment] = useState(false);

  useEffect(() => {
    if (address) {
      const commitmentData = getCommitmentData(address);
      setHasCommitment(!!commitmentData);
    }
  }, [address]);

  async function handleBorrow() {
    if (!account || !address) {
      setStatus("Please connect wallet");
      return;
    }

    const commitmentData = getCommitmentData(address);
    if (!commitmentData) {
      setStatus("No deposit found. Please deposit first.");
      return;
    }

    if (!borrowAmount || parseFloat(borrowAmount) <= 0) {
      setStatus("Please enter a valid borrow amount");
      return;
    }

    setIsGenerating(true);
    setStatus("Generating zero-knowledge proof...");

    try {
      // Fetch current prices (simplified - in production, fetch from oracle)
      const btcPrice = "65000000000"; // $65,000 with 6 decimals
      const usdcPrice = "1000000"; // $1 with 6 decimals
      const minHealthFactor = "110"; // 1.10

      // Convert borrow amount to USDC (6 decimals)
      const borrowAmountBigInt = BigInt(Math.floor(parseFloat(borrowAmount) * 1000000));

      // Generate proof
      setStatus("Generating proof... This may take a few seconds.");
      const proof = await generateBorrowProof({
        owner_address: address,
        btc_amount: commitmentData.btcAmount,
        salt: commitmentData.salt,
        merkle_path: commitmentData.merklePath,
        merkle_indices: commitmentData.merkleIndices.map(Number),
        borrow_amount: borrowAmountBigInt.toString(),
        btc_price: btcPrice,
        usdc_price: usdcPrice,
        min_health_factor: minHealthFactor,
        merkle_root: commitmentData.merkleRoot,
      });

      setStatus("Proof generated. Submitting to contract...");

      // Submit borrow transaction
      const vaultClient = new VaultClient(account);
      const txHash = await vaultClient.borrow(
        proof.proof,
        proof.publicInputs,
        address // Could be stealth address
      );

      setStatus(`Success! Transaction: ${txHash.slice(0, 10)}...`);
    } catch (error: any) {
      setStatus(`Error: ${error.message}`);
    } finally {
      setIsGenerating(false);
    }
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-2xl mx-auto">
        <div className="mb-6">
          <Link href="/" className="text-blue-600 hover:underline">
            ← Back to Home
          </Link>
        </div>

        <h1 className="text-3xl font-bold mb-6">Borrow USDC</h1>

        <div className="mb-6">
          <WalletConnect />
        </div>

        {account && (
          <div className="bg-white p-6 rounded-lg shadow">
            {!hasCommitment && (
              <div className="mb-4 p-4 bg-yellow-50 border border-yellow-200 rounded">
                <p className="text-sm text-yellow-800">
                  You need to deposit first before borrowing.{" "}
                  <Link href="/deposit" className="underline">
                    Go to Deposit
                  </Link>
                </p>
              </div>
            )}

            {hasCommitment && (
              <>
                <div className="mb-4">
                  <label className="block text-sm font-medium mb-2">
                    Borrow Amount (USDC)
                  </label>
                  <input
                    type="number"
                    value={borrowAmount}
                    onChange={(e) => setBorrowAmount(e.target.value)}
                    className="w-full px-3 py-2 border rounded"
                    placeholder="10000"
                    disabled={isGenerating}
                  />
                  <p className="text-xs text-gray-500 mt-1">
                    Your borrow amount will be verified via zero-knowledge proof
                  </p>
                </div>

                <button
                  onClick={handleBorrow}
                  disabled={isGenerating || !borrowAmount}
                  className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:bg-gray-400"
                >
                  {isGenerating ? "Generating Proof..." : "Borrow with Privacy"}
                </button>

                {status && (
                  <div className={`mt-4 p-3 rounded text-sm ${
                    status.includes("Error") ? "bg-red-100 text-red-800" : "bg-blue-100 text-blue-800"
                  }`}>
                    {status}
                  </div>
                )}

                {isGenerating && (
                  <div className="mt-4 p-3 bg-gray-50 rounded">
                    <div className="text-sm text-gray-600">
                      Proof generation can take 5-10 seconds. Please wait...
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        )}

        {!account && (
          <div className="bg-yellow-50 p-4 rounded-lg">
            <p className="text-sm text-yellow-800">
              Please connect your wallet to borrow.
            </p>
          </div>
        )}

        <div className="mt-6 p-4 bg-gray-50 rounded-lg">
          <h2 className="font-semibold mb-2">How Privacy Borrowing Works</h2>
          <ul className="text-sm text-gray-700 space-y-1 list-disc list-inside">
            <li>Generate a zero-knowledge proof that proves you can safely borrow</li>
            <li>Your individual position details remain hidden</li>
            <li>Only aggregate health factor is public</li>
            <li>Prevents liquidation hunting and MEV attacks</li>
          </ul>
        </div>
      </div>
    </main>
  );
}
