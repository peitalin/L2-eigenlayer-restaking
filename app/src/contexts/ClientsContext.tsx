import React, { createContext, useContext, ReactNode, useState, useEffect } from 'react';
import { useClients, ClientsState } from '../hooks/useClients';
import { getEigenAgentAndExecNonce, predictEigenAgentAddress } from '../utils/eigenlayerUtils';
import { Address } from 'viem';
import { EigenAgentInfo } from '../types';

// Extend the ClientsState with EigenAgent info
interface ExtendedClientsState extends ClientsState {
  eigenAgentInfo: EigenAgentInfo | null;
  isLoadingEigenAgent: boolean;
  predictedEigenAgentAddress: Address | null;
  isFirstTimeUser: boolean;
  fetchEigenAgentInfo: () => Promise<void>;
  handleConnect: () => Promise<void>;
  isConnecting: boolean;
  connectionError: string | null;
}

// Create a context with a default empty value
const ClientsContext = createContext<ExtendedClientsState | null>(null);

interface ClientsProviderProps {
  children: ReactNode;
}

/**
 * Provider component that wraps app and makes client state available to any
 * child component that calls useClientsContext()
 */
export const ClientsProvider: React.FC<ClientsProviderProps> = ({ children }) => {
  const clientsState = useClients();
  const { isConnected, l1Wallet, connect } = clientsState;
  const [eigenAgentInfo, setEigenAgentInfo] = useState<EigenAgentInfo | null>(null);
  const [predictedEigenAgentAddress, setPredictedEigenAgentAddress] = useState<Address | null>(null);
  const [isLoadingEigenAgent, setIsLoadingEigenAgent] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [connectionAttempted, setConnectionAttempted] = useState(false);

  // Fetch EigenAgent info whenever L1 account changes
  useEffect(() => {
    if (l1Wallet.account) {
      fetchEigenAgentInfo();
    }
  }, [l1Wallet.account]);

  // Function to fetch EigenAgent info
  const fetchEigenAgentInfo = async () => {
    if (!l1Wallet.account) return;

    setIsLoadingEigenAgent(true);
    try {
      // Fetch current EigenAgent info
      const info = await getEigenAgentAndExecNonce(l1Wallet.account);
      setEigenAgentInfo(info);

      // If user doesn't have an EigenAgent, predict what it will be
      if (!info) {
        const predicted = await predictEigenAgentAddress(l1Wallet.account);
        setPredictedEigenAgentAddress(predicted);
      } else {
        setPredictedEigenAgentAddress(null);
      }
    } catch (err) {
      console.error('Error checking EigenAgent:', err);
      setEigenAgentInfo(null);
    } finally {
      setIsLoadingEigenAgent(false);
    }
  };

  // Handle wallet connection
  const handleConnect = async () => {
    setIsConnecting(true);
    setConnectionError(null);
    setConnectionAttempted(true);

    try {
      await connect();
    } catch (err) {
      console.error('Error connecting wallet:', err);
      setConnectionError(err instanceof Error ? err.message : 'Failed to connect wallet');
    } finally {
      setIsConnecting(false);
    }
  };

  // Determine if this is a first-time user (no EigenAgent yet)
  const isFirstTimeUser = eigenAgentInfo === null && !isLoadingEigenAgent && isConnected;

  // Combine the client state with EigenAgent info and connection handlers
  const extendedState: ExtendedClientsState = {
    ...clientsState,
    eigenAgentInfo,
    isLoadingEigenAgent,
    predictedEigenAgentAddress,
    isFirstTimeUser,
    fetchEigenAgentInfo,
    handleConnect,
    isConnecting,
    connectionError
  };

  // Always provide the context to children, regardless of connection state
  return (
    <ClientsContext.Provider value={extendedState}>
      {children}
    </ClientsContext.Provider>
  );
};

/**
 * Hook for components to get the clients state
 * and re-render when it changes
 */
export const useClientsContext = (): ExtendedClientsState => {
  const context = useContext(ClientsContext);

  if (context === null) {
    throw new Error('useClientsContext must be used within a ClientsProvider');
  }

  return context;
};