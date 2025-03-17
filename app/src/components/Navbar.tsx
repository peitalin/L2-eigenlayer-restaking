import React from 'react';
import { useClientsContext } from '../contexts/ClientsContext';

const shortenAddress = (address: string): string => {
  if (!address) return '';
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
};

interface NavbarProps {}

const Navbar: React.FC<NavbarProps> = () => {
  const {
    l1Wallet,
    l2Wallet,
    selectedChain,
    isConnected,
    handleConnect,
    disconnect,
    isConnecting,
    connectionError
  } = useClientsContext();

  // Sepolia chain ID is 11155111
  const isEthereumChain = selectedChain.id === 11155111;
  const currentWallet = isEthereumChain ? l1Wallet : l2Wallet;

  return (
    <div className="navbar">
      <div className="navbar-title">
      </div>
      <div className="navbar-actions">
        {isConnected ? (
          <div className="navbar-wallet-info">
            <div className="wallet-info">
              <div className="current-chain">
                {isEthereumChain ? 'Ethereum Sepolia' : 'Base Sepolia'}
              </div>
              <div className="current-account">
                {currentWallet.account && shortenAddress(currentWallet.account)}
              </div>
            </div>
            <button
              className="disconnect-button"
              onClick={disconnect}
            >
              Disconnect
            </button>
          </div>
        ) : (
          <button
            className="connect-button"
            onClick={handleConnect}
            disabled={isConnecting}
          >
            {isConnecting ? 'Connecting...' : 'Connect'}
          </button>
        )}
      </div>
      {connectionError && (
        <div className="connection-error">
          Error connecting: {connectionError}
        </div>
      )}
    </div>
  );
};

export default Navbar;