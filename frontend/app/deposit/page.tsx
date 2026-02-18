"use client";

import { useState } from "react";
import { useAccount } from "@starknet-react/core";
import { VaultClient } from "@/lib/vault-contract";
import { saveCommitmentData } from "@/lib/commitment-storage";
import { WalletConnect } from "@/components/WalletConnect";
import Link from "next/link";

export default function DepositPage() {
  const { account, address } = useAccount();
  const [amount, setAmount] = useState("");
  const [isProcessing, setIsProcessing] = useState(false);
  const [status, setStatus] = useState("");
  const [commitment, setCommitment] = useState("");

  async function handleDeposit() {
    if (!account || !address) {
      setStatus("Please connect wallet");
      return;
    }

    if (!amount || parseFloat(amount) <= 0) {
      setStatus("Please enter a valid amount");
      return;
    }

    setIsProcessing(true);
    setStatus("Processing deposit...");

    try {
      const amountBigInt = BigInt(Math.floor(parseFloat(amount) * 100000000));
      const vaultClient = new VaultClient(account);

      const { commitment: commitmentHash, leafIndex, salt } = await vaultClient.deposit(amountBigInt);

      const { path: merklePath, indices: merkleIndices } = await vaultClient.getMerkleProof(leafIndex);
      const merkleRoot = await vaultClient.getMerkleRoot();

      saveCommitmentData(address, {
        btcAmount: amountBigInt.toString(),
        salt,
        merklePath,
        merkleIndices,
        merkleRoot,
        commitment: commitmentHash,
        timestamp: Date.now(),
      });

      setCommitment(commitmentHash);
      setStatus(`Success! Commitment: ${commitmentHash.slice(0, 10)}...`);
    } catch (error: any) {
      setStatus(`Error: ${error.message}`);
    } finally {
      setIsProcessing(false);
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

        <h1 className="text-3xl font-bold mb-6">Deposit WBTC</h1>

        <div className="mb-6">
          <WalletConnect />
        </div>

        {account && (
          <div className="bg-white p-6 rounded-lg shadow">
            <div className="mb-4">
              <label className="block text-sm font-medium mb-2">
                Amount (WBTC)
              </label>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="w-full px-3 py-2 border rounded"
                placeholder="1.0"
                step="0.00000001"
                disabled={isProcessing}
              />
            </div>

            <button
              onClick={handleDeposit}
              disabled={isProcessing || !amount}
              className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:bg-gray-400"
            >
              {isProcessing ? "Processing..." : "Deposit"}
            </button>

            {status && (
              <div className={`mt-4 p-3 rounded text-sm ${
                status.includes("Error") ? "bg-red-100 text-red-800" : "bg-green-100 text-green-800"
              }`}>
                {status}
              </div>
            )}

            {commitment && (
              <div className="mt-4 p-3 bg-gray-100 rounded">
                <div className="text-sm font-semibold mb-2">Your Commitment:</div>
                <div className="font-mono text-xs break-all">{commitment}</div>
                <div className="text-xs text-gray-600 mt-2">
                  Save this commitment! You'll need it to borrow.
                </div>
              </div>
            )}
          </div>
        )}

        {!account && (
          <div className="bg-yellow-50 p-4 rounded-lg">
            <p className="text-sm text-yellow-800">
              Please connect your wallet to deposit.
            </p>
          </div>
        )}
      </div>
    </main>
  );
}
