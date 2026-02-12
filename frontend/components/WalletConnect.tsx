"use client";

import { useAccount, useConnect, useDisconnect } from "@starknet-react/core";
import { useEffect } from "react";

export function WalletConnect() {
  const { account, address, status } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();

  useEffect(() => {
    // Auto-connect if previously connected
    const storedConnector = localStorage.getItem("starknet-connector");
    if (storedConnector && connectors.length > 0) {
      const connector = connectors.find((c) => c.id === storedConnector);
      if (connector && !account) {
        connect({ connector });
      }
    }
  }, [connect, connectors, account]);

  const handleConnect = (connectorId: string) => {
    const connector = connectors.find((c) => c.id === connectorId);
    if (connector) {
      connect({ connector });
      localStorage.setItem("starknet-connector", connectorId);
    }
  };

  const handleDisconnect = () => {
    disconnect();
    localStorage.removeItem("starknet-connector");
  };

  if (account && address) {
    return (
      <div className="flex items-center gap-4">
        <div className="text-sm">
          <div className="font-semibold">Connected</div>
          <div className="text-gray-600 font-mono text-xs">
            {address.slice(0, 6)}...{address.slice(-4)}
          </div>
        </div>
        <button
          onClick={handleDisconnect}
          className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="text-sm font-semibold mb-2">Connect Wallet</div>
      <div className="flex gap-2">
        {connectors.map((connector) => (
          <button
            key={connector.id}
            onClick={() => handleConnect(connector.id)}
            disabled={status === "connecting"}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400"
          >
            {connector.name}
          </button>
        ))}
      </div>
      {status === "connecting" && (
        <div className="text-sm text-gray-600">Connecting...</div>
      )}
    </div>
  );
}
