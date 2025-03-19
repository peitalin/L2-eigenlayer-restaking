import React, { ReactNode, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
// Contexts
import { ClientsProvider } from './contexts/ClientsContext';
import { TransactionHistoryProvider } from './contexts/TransactionHistoryContext';
import { useClientsContext } from './contexts/ClientsContext';
// Pages
import WithdrawalPage from './pages/WithdrawalPage';
import DepositPage from './pages/DepositPage';
import TransactionsPage from './pages/TransactionsPage';
// Layout Components
import Navbar from './components/Navbar';
import Navigation from './components/Navigation';
import EigenAgentInfo from './components/EigenAgentInfo';
import RewardsComponent from './components/RewardsComponent';
// Toast
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

function App() {
  return (
    <ClientsProvider>
      <TransactionHistoryProvider>
        <Router>
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
            <Route path="/withdrawal" element={
              <Layout>
                <WithdrawalPage />
              </Layout>
            } />
            <Route path="/transactions" element={
              <Layout fullWidth>
                <TransactionsPage />
              </Layout>
            } />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Router>
        <ToastContainer
          position="top-right"
          autoClose={4000}
          hideProgressBar={false}
          newestOnTop
          closeOnClick
          rtl={false}
          pauseOnFocusLoss
          draggable
          pauseOnHover
        />
      </TransactionHistoryProvider>
    </ClientsProvider>
  );
}

interface LayoutProps {
  children?: ReactNode;
  fullWidth?: boolean
}

const Layout: React.FC<LayoutProps> = ({ children, fullWidth = false }) => {
  return (
    <div className="app-container">
      <Navbar />
      <Navigation />
      <div className="content-container">
          <div className={`page-layout ${fullWidth && 'transactions-page-layout'}`}>
            <div className={`left-column ${fullWidth && 'full-width'}`}>
              {children}
            </div>
            {
              !fullWidth && (
                <div className="right-column">
                  <EigenAgentInfo />
                  <RewardsComponent />
                </div>
              )
            }
          </div>
      </div>
    </div>
  );
};

export default App;