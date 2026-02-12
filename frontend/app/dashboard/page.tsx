"use client";

import { useState, useEffect } from "react";
import { VaultClient } from "@/lib/vault-contract";
import { WalletConnect } from "@/components/WalletConnect";
import Link from "next/link";

export default function DashboardPage() {
  const [healthData, setHealthData] = useState<{
    collateralUsd: bigint;
    debtUsd: bigint;
    healthFactor: number;
  } | null>(null);
  const [totalDeposited, setTotalDeposited] = useState<bigint | null>(null);
  const [totalBorrowed, setTotalBorrowed] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadDashboardData();
    const interval = setInterval(loadDashboardData, 30000); // Refresh every 30s
    return () => clearInterval(interval);
  }, []);

  async function loadDashboardData() {
    try {
      setLoading(true);
      const vaultClient = new VaultClient();

      const [health, deposited, borrowed] = await Promise.all([
        vaultClient.getAggregateHealth(),
        vaultClient.getTotalDeposited(),
        vaultClient.getTotalBorrowed(),
      ]);

      setHealthData(health);
      setTotalDeposited(deposited);
      setTotalBorrowed(borrowed);
      setError(null);
    } catch (err: any) {
      setError(err.message || "Failed to load dashboard data");
    } finally {
      setLoading(false);
    }
  }

  function formatUSD(value: bigint): string {
    const num = Number(value) / 1e6; // Assuming 6 decimals
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
    }).format(num);
  }

  function formatBTC(value: bigint): string {
    const num = Number(value) / 1e8; // 8 decimals for BTC
    return `${num.toFixed(8)} BTC`;
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <div className="mb-6">
          <Link href="/" className="text-blue-600 hover:underline">
            ← Back to Home
          </Link>
        </div>

        <h1 className="text-3xl font-bold mb-6">Vault Dashboard</h1>

        <div className="mb-6">
          <WalletConnect />
        </div>

        {loading && (
          <div className="bg-white p-6 rounded-lg shadow text-center">
            <div className="text-gray-600">Loading dashboard data...</div>
          </div>
        )}

        {error && (
          <div className="bg-red-50 p-4 rounded-lg border border-red-200">
            <p className="text-red-800 text-sm">{error}</p>
          </div>
        )}

        {!loading && !error && healthData && (
          <div className="space-y-6">
            {/* Health Factor Card */}
            <div className="bg-white p-6 rounded-lg shadow">
              <h2 className="text-xl font-semibold mb-4">Aggregate Health Factor</h2>
              <div className="text-4xl font-bold mb-2">
                {healthData.healthFactor.toFixed(2)}x
              </div>
              <div className="text-sm text-gray-600">
                {healthData.healthFactor >= 1.5 ? (
                  <span className="text-green-600">Healthy</span>
                ) : healthData.healthFactor >= 1.1 ? (
                  <span className="text-yellow-600">Moderate</span>
                ) : (
                  <span className="text-red-600">At Risk</span>
                )}
              </div>

              {/* Health Factor Bar */}
              <div className="mt-4 w-full bg-gray-200 rounded-full h-4">
                <div
                  className={`h-4 rounded-full ${
                    healthData.healthFactor >= 1.5
                      ? "bg-green-500"
                      : healthData.healthFactor >= 1.1
                      ? "bg-yellow-500"
                      : "bg-red-500"
                  }`}
                  style={{
                    width: `${Math.min((healthData.healthFactor / 2) * 100, 100)}%`,
                  }}
                />
              </div>
            </div>

            {/* Metrics Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="bg-white p-6 rounded-lg shadow">
                <h3 className="text-sm font-medium text-gray-600 mb-2">
                  Total Collateral (USD)
                </h3>
                <div className="text-2xl font-bold">
                  {formatUSD(healthData.collateralUsd)}
                </div>
              </div>

              <div className="bg-white p-6 rounded-lg shadow">
                <h3 className="text-sm font-medium text-gray-600 mb-2">
                  Total Debt (USD)
                </h3>
                <div className="text-2xl font-bold">
                  {formatUSD(healthData.debtUsd)}
                </div>
              </div>

              <div className="bg-white p-6 rounded-lg shadow">
                <h3 className="text-sm font-medium text-gray-600 mb-2">
                  Total Deposited (WBTC)
                </h3>
                <div className="text-2xl font-bold">
                  {totalDeposited ? formatBTC(totalDeposited) : "N/A"}
                </div>
              </div>

              <div className="bg-white p-6 rounded-lg shadow">
                <h3 className="text-sm font-medium text-gray-600 mb-2">
                  Total Borrowed (USDC)
                </h3>
                <div className="text-2xl font-bold">
                  {totalBorrowed ? formatUSD(totalBorrowed) : "N/A"}
                </div>
              </div>
            </div>

            {/* Privacy Notice */}
            <div className="bg-blue-50 p-4 rounded-lg border border-blue-200">
              <h3 className="font-semibold text-blue-900 mb-2">Privacy Notice</h3>
              <p className="text-sm text-blue-800">
                This dashboard shows only aggregate vault metrics. Individual user positions,
                liquidation prices, and health factors are kept private through zero-knowledge proofs.
                This prevents MEV bots and liquidation hunters from targeting specific users.
              </p>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
