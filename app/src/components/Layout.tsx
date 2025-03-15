import React, { ReactNode, useEffect } from 'react';
import Navbar from './Navbar';
import { useClientsContext } from '../contexts/ClientsContext';

interface LayoutProps {
  children: ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const {
    l1WalletClient,
    l2WalletClient,
    l1PublicClient,
    l2PublicClient,
    l1Account,
    l2Account,
    selectedChain,
    isConnected,
    disconnect,
    switchChain,
    l1Balance,
    l2Balance,
    isLoadingBalance,
    refreshBalances
  } = useClientsContext();

  // Get the appropriate account and balance based on the selected chain
  const currentAccount = selectedChain.id === (l1PublicClient.chain?.id ?? 11155111) ? l1Account : l2Account;
  const currentBalance = selectedChain.id === (l1PublicClient.chain?.id ?? 11155111) ? l1Balance : l2Balance;

  return (
    <div className="app-container">
      <Navbar
        selectedChain={selectedChain}
        account={currentAccount}
        isConnected={isConnected}
        onDisconnect={disconnect}
      />

      <div className="content-container">
        {children}
      </div>
    </div>
  );
};

export default Layout;