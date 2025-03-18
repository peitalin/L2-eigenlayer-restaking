import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ClientsProvider } from './contexts/ClientsContext';
import { TransactionHistoryProvider } from './contexts/TransactionHistoryContext';
import { ToastProvider } from './components/ToastContainer';
import Layout from './components/Layout';
import WithdrawalPage from './components/WithdrawalPage';
import DepositPage from './pages/DepositPage';
import TransactionsPage from './pages/TransactionsPage';
import ToastContainer from './components/ToastContainer';
import { useCCIPMessageStatusChecker } from './utils/ccipDataFetcher';
import { useClientsContext } from './contexts/ClientsContext';
import { useCompleteWithdrawalMonitor } from './contexts/TransactionHistoryContext';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

// Create a CCIP status monitoring component
const CCIPStatusMonitor: React.FC = () => {
  const { l2Wallet } = useClientsContext();
  const { startChecking, stopChecking } = useCCIPMessageStatusChecker(60000); // Check every minute
  const { startMonitoring, stopMonitoring } = useCompleteWithdrawalMonitor(60000); // Check every minute

  useEffect(() => {
    if (l2Wallet.publicClient) {
      console.log('Starting CCIP status monitoring...');
      const cleanupCCIP = startChecking(l2Wallet.publicClient);

      console.log('Starting withdrawal completion monitoring...');
      const cleanupWithdrawals = startMonitoring();

      return () => {
        console.log('Stopping CCIP status monitoring...');
        cleanupCCIP();
        stopChecking();

        console.log('Stopping withdrawal completion monitoring...');
        cleanupWithdrawals();
        stopMonitoring();
      };
    }
  }, [l2Wallet.publicClient, startChecking, stopChecking, startMonitoring, stopMonitoring]);

  // This component doesn't render anything
  return null;
};

function App() {
  return (
    <Router>
      <ClientsProvider>
        <TransactionHistoryProvider>
          <ToastProvider>
            <Layout>
              <Routes>
                <Route path="/" element={<DepositPage />} />
                <Route path="/deposit" element={<DepositPage />} />
                <Route path="/withdraw" element={<WithdrawalPage />} />
                <Route path="/transactions" element={<TransactionsPage />} />
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </Layout>
            <ToastContainer />
            <CCIPStatusMonitor />
          </ToastProvider>
        </TransactionHistoryProvider>
      </ClientsProvider>
    </Router>
  );
}

export default App;