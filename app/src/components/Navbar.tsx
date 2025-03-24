import React from 'react';
import { useClientsContext } from '../contexts/ClientsContext';
import { formatEther } from 'viem';
import TransactionHistoryDropdown from './TransactionHistoryDropdown';

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
    connectionError,
    refreshBalances,
    isLoadingBalance
  } = useClientsContext();

  // Sepolia chain ID is 11155111
  const isEthereumChain = selectedChain.id === 11155111;
  const currentWallet = isEthereumChain ? l1Wallet : l2Wallet;

  return (
    <div className="navbar">
      <div className="navbar-title">
        {isConnected && (
          <div className="navbar-balances">
            <div className="navbar-logo">
              <div style={{ position: 'relative', width: '120px', height: '32px' }}>
                <img
                  src="/assets/logos/treasure/eigenlayer-logo.webp"
                  alt="EigenLayer Logo"
                  style={{
                    position: 'absolute',
                    left: '0',
                    top: '2px',
                    width: '24px',
                    height: '24px',
                    borderRadius: '8px',
                    padding: '2px',
                    backgroundColor: 'white',
                    objectFit: 'contain',
                    zIndex: 1
                  }}
                />
                <img
                  src="/assets/logos/treasure/treasure-logo.svg"
                  alt="Treasure"
                  style={{
                    position: 'absolute',
                    left: '24px',
                    height: '32px',
                    zIndex: 2
                  }}
                />
              </div>
            </div>
          </div>
        )}
      </div>
      <div className="navbar-actions">
        <div className="navbar-transactions">
          <TransactionHistoryDropdown />
        </div>
        {isConnected ? (
          <div className="navbar-wallet-info">
            <div className="wallet-info">
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