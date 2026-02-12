import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-4xl font-bold mb-4">VestaZk</h1>
        <p className="text-lg mb-8 text-gray-600">
          Privacy-preserving lending vault on Starknet that prevents liquidation hunting
        </p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <Link
            href="/deposit"
            className="p-6 border rounded-lg hover:bg-gray-50 transition"
          >
            <h2 className="text-xl font-semibold mb-2">Deposit</h2>
            <p className="text-gray-600">Deposit WBTC and receive a privacy commitment</p>
          </Link>

          <Link
            href="/borrow"
            className="p-6 border rounded-lg hover:bg-gray-50 transition"
          >
            <h2 className="text-xl font-semibold mb-2">Borrow</h2>
            <p className="text-gray-600">Borrow USDC using zero-knowledge proofs</p>
          </Link>

          <Link
            href="/dashboard"
            className="p-6 border rounded-lg hover:bg-gray-50 transition"
          >
            <h2 className="text-xl font-semibold mb-2">Dashboard</h2>
            <p className="text-gray-600">View aggregate vault metrics</p>
          </Link>
        </div>

        <div className="mt-8 p-6 bg-blue-50 rounded-lg">
          <h2 className="text-xl font-semibold mb-2">How It Works</h2>
          <ul className="list-disc list-inside space-y-2 text-gray-700">
            <li>Deposit WBTC through the privacy vault</li>
            <li>Receive a commitment hash (your position is hidden)</li>
            <li>Borrow USDC using ZK proofs without revealing your position</li>
            <li>Only aggregate health factor is public, preventing targeted attacks</li>
          </ul>
        </div>
      </div>
    </main>
  );
}
