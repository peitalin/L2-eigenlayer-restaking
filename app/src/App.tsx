import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ClientsProvider } from './contexts/ClientsContext';
import { TransactionHistoryProvider } from './contexts/TransactionHistoryContext';
import { ToastProvider } from './components/ToastContainer';
import Layout from './components/Layout';
import DepositPage from './components/DepositPage';
import WithdrawalPage from './components/WithdrawalPage';
import ToastContainer from './components/ToastContainer';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

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
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </Layout>
            <ToastContainer />
          </ToastProvider>
        </TransactionHistoryProvider>
      </ClientsProvider>
    </Router>
  );
}

export default App;