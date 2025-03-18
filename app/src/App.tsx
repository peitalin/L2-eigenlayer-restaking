import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ClientsProvider } from './contexts/ClientsContext';
import { TransactionHistoryProvider, useTransactionHistoryPolling } from './contexts/TransactionHistoryContext';
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';
import Layout from './components/Layout';
import WithdrawalPage from './pages/WithdrawalPage';
import DepositPage from './pages/DepositPage';
import TransactionsPage from './pages/TransactionsPage';
import { useClientsContext } from './contexts/ClientsContext';
import Navbar from './components/Navbar';
import Navigation from './components/Navigation';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

// Create a CCIP status monitoring component
const CCIPStatusMonitor: React.FC = () => {
  const { l2Wallet } = useClientsContext();
  const polling = useTransactionHistoryPolling(); // Get the polling object but don't destructure it

  useEffect(() => {
    if (l2Wallet.publicClient) {
      console.log('Starting transaction history polling...');
      polling.startPolling(); // Use the method on the object instead

      return () => {
        console.log('Stopping transaction history polling...');
        polling.stopPolling(); // Use the method on the object instead
      };
    }
  }, [l2Wallet.publicClient, polling]); // Only depend on the polling object itself, not the individual methods

  // This component doesn't render anything
  return null;
};

// Custom layout for transactions page (without right column)
const TransactionsLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return (
    <div className="app-container">
      <Navbar />
      <Navigation />
      <div className="content-container">
        <div className="page-layout transactions-page-layout">
          <div className="left-column full-width">
            {children}
          </div>
        </div>
      </div>
    </div>
  );
};

function App() {
  return (
    <Router>
      <ClientsProvider>
        <TransactionHistoryProvider>
          <Routes>
            <Route path="/" element={
              <Layout>
                <DepositPage />
              </Layout>
            } />
            <Route path="/deposit" element={
              <Layout>
                <DepositPage />
              </Layout>
            } />
            <Route path="/withdraw" element={
              <Layout>
                <WithdrawalPage />
              </Layout>
            } />
            <Route path="/transactions" element={
              <TransactionsLayout>
                <TransactionsPage />
              </TransactionsLayout>
            } />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
          {/* React-toastify container with configuration */}
          <ToastContainer
            position="top-right"
            autoClose={5000}
            hideProgressBar={false}
            newestOnTop
            closeOnClick
            rtl={false}
            pauseOnFocusLoss
            draggable
            pauseOnHover
          />
          <CCIPStatusMonitor />
        </TransactionHistoryProvider>
      </ClientsProvider>
    </Router>
  );
}

export default App;