import React, { useState, ReactNode, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { baseSepolia } from '../hooks/useClients';
import { useClientsContext } from '../contexts/ClientsContext';

interface WalletConnectProps {
  children: ReactNode;
}

const WalletConnect: React.FC<WalletConnectProps> = ({ children }) => {
  const { connect, isConnected, l1Account, l2Account } = useClientsContext();
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const handleConnect = async () => {
    setIsConnecting(true);
    setError(null);

    try {
      await connect();
    } catch (err) {
      console.error('Error connecting wallet:', err);
      setError(err instanceof Error ? err.message : 'Failed to connect wallet');
    } finally {
      setIsConnecting(false);
    }
  };

  // If already connected, render children
  if (isConnected && l2Account) {
    return <>{children}</>;
  }

  // Otherwise, show connect wallet UI
  return (
    <div className="wallet-connect-page">
      <h1>EigenLayer L2 Restaking</h1>

      <div className="connect-container">
        <button
          onClick={handleConnect}
          disabled={isConnecting}
          className="connect-button"
        >
          {isConnecting ? 'Connecting...' : `Connect to ${baseSepolia.name}`}
        </button>

        {error && (
          <div className="error-message">
            {error}
          </div>
        )}
      </div>
    </div>
  );
};

export default WalletConnect;
