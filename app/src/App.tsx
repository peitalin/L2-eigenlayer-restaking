import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Layout from './components/Layout';
import HomePage from './components/HomePage';
import WalletConnect from './components/WalletConnect';
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
        <WalletConnect>
          <Layout>
            <Routes>
              <Route path="/" element={<HomePage />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </Layout>
        </WalletConnect>
      </ClientsProvider>
    </BrowserRouter>
  );
}

export default App;