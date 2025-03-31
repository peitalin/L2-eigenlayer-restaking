import React, { useState } from 'react';
import { useClientsContext } from '../contexts/ClientsContext';
import { formatEther } from 'viem';
import TransactionHistoryDropdown from './TransactionHistoryDropdown';
import { FaucetL2 } from '../addresses';
import { FaucetABI } from '../abis';
import { useToast } from '../utils/toast';

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

  const [isClaiming, setIsClaiming] = useState(false);
  const { showToast } = useToast();

  // Sepolia chain ID is 11155111
  const isEthereumChain = selectedChain.id === 11155111;
  const currentWallet = isEthereumChain ? l1Wallet : l2Wallet;

  const handleClaim = async () => {
    if (!currentWallet.account || !currentWallet.publicClient || !currentWallet.walletClient) {
      showToast('Please connect your wallet first', 'error');
      return;
    }

    try {
      setIsClaiming(true);
      const amount = BigInt('1000000000000000000'); // 1 token with 18 decimals

      // First simulate the transaction
      const { request } = await currentWallet.publicClient.simulateContract({
        address: FaucetL2,
        abi: FaucetABI,
        functionName: 'claim',
        args: [amount],
        account: currentWallet.account,
      });

      showToast('Claim simulation successful! Please confirm the transaction.', 'info');

      // Send the transaction
      const hash = await currentWallet.walletClient.writeContract(request);
      showToast('Claim transaction submitted! Waiting for confirmation...', 'info');

      // Wait for transaction confirmation
      const receipt = await currentWallet.publicClient.waitForTransactionReceipt({ hash });

      if (receipt.status === 'success') {
        showToast('Successfully claimed tokens!', 'success');
        // Refresh balances after successful claim
        refreshBalances?.();
      } else {
        showToast('Transaction failed. Please try again.', 'error');
      }
    } catch (error) {
      console.error('Error claiming tokens:', error);
      if (error instanceof Error) {
        if (error.message.includes('user rejected')) {
          showToast('Transaction was rejected by user', 'info');
        } else if (error.message.includes('ClaimLimitExceeded')) {
          showToast('You have exceeded your claim limit', 'error');
        } else if (error.message.includes('InsufficientFaucetBalance')) {
          showToast('The faucet has insufficient balance', 'error');
        } else {
          showToast(`Error claiming tokens: ${error.message}`, 'error');
        }
      } else {
        showToast('An unknown error occurred while claiming tokens', 'error');
      }
    } finally {
      setIsClaiming(false);
    }
  };

  return (
    <div className="navbar">
      <div className="navbar-title">
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
      </div>
      <div className="navbar-actions">
        {isConnected && !isEthereumChain && (
          <button
            className="claim-button"
            onClick={handleClaim}
            disabled={isClaiming}
            style={{
              padding: '0.5rem 1rem',
              borderRadius: '4px',
              backgroundColor: 'var(--treasure-accent-secondary)',
              color: 'white',
              border: 'none',
              cursor: isClaiming ? 'not-allowed' : 'pointer',
              opacity: isClaiming ? 0.7 : 1
            }}
          >
            {isClaiming ? 'Claiming...' : 'Claim'}
          </button>
        )}
        <div className="navbar-transactions">
          {isConnected && <TransactionHistoryDropdown />}
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