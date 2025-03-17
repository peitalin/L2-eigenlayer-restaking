import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Layout from './components/Layout';
import DepositPage from './components/DepositPage';
import WithdrawalPage from './components/WithdrawalPage';
import { ClientsProvider } from './contexts/ClientsContext';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

function App() {
  return (
    <BrowserRouter>
      <ClientsProvider>
        <Layout>
          <Routes>
            <Route path="/" element={<DepositPage />} />
            <Route path="/withdraw" element={<WithdrawalPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Layout>
      </ClientsProvider>
    </BrowserRouter>
  );
}

export default App;