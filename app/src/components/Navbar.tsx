import React from 'react';
import { Chain, Address } from 'viem';

interface NavbarProps {
  selectedChain: Chain;
  account: Address | null;
  isConnected: boolean;
  onDisconnect: () => void;
}

const Navbar: React.FC<NavbarProps> = ({
  selectedChain,
  account,
  isConnected,
  onDisconnect
}) => {
  // Format the wallet address for display
  const formatAddress = (address: string) => {
    return `${address.substring(0, 6)}...${address.substring(38)}`;
  };

  if (!isConnected) {
    return null;
  }

  return (
    <div className="wallet-navbar">
      <div className="navbar-info">
        <div className="navbar-section">
          <span className="section-label">Current Chain:</span>
          <span className="section-value">{selectedChain.name}</span>
        </div>

        <div className="navbar-section">
          <span className="section-label">Connected Wallet:</span>
          <span className="section-value wallet-address-short">
            {account ? formatAddress(account) : 'Not connected'}
          </span>
        </div>
      </div>

      <button
        onClick={onDisconnect}
        className="disconnect-button"
      >
        Disconnect
      </button>
    </div>
  );
};

export default Navbar;