import React, { createContext, useContext, ReactNode, useState, useEffect, useRef } from 'react';
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

  // Add refs to track fetch state
  const lastFetchTimestamp = useRef<number>(0);
  const fetchCooldown = 5000; // 5 seconds cooldown between fetches
  const isFetching = useRef<boolean>(false);

  // Function to fetch EigenAgent info with cooldown and state tracking
  const fetchEigenAgentInfo = async () => {
    // Don't fetch if:
    // 1. No wallet connected
    // 2. Already fetching
    // 3. Not enough time has passed since last fetch
    // 4. We already have eigenAgentInfo
    if (!l1Wallet.account ||
        isFetching.current ||
        Date.now() - lastFetchTimestamp.current < fetchCooldown ||
        (eigenAgentInfo && !isLoadingEigenAgent)) {
      return;
    }

    isFetching.current = true;
    setIsLoadingEigenAgent(true);

    try {
      // Fetch current EigenAgent info
      const info = await getEigenAgentAndExecNonce(l1Wallet.account);
      setEigenAgentInfo(info);

      // Only predict address if we don't have an EigenAgent and haven't predicted one yet
      if (!info && !predictedEigenAgentAddress) {
        const predicted = await predictEigenAgentAddress(l1Wallet.account);
        setPredictedEigenAgentAddress(predicted);
      } else if (info) {
        // Clear predicted address if we have an actual EigenAgent
        setPredictedEigenAgentAddress(null);
      }
    } catch (err) {
      console.error('Error checking EigenAgent:', err);
      setEigenAgentInfo(null);
      setPredictedEigenAgentAddress(null);
    } finally {
      setIsLoadingEigenAgent(false);
      isFetching.current = false;
      lastFetchTimestamp.current = Date.now();
    }
  };

  // Single useEffect to handle EigenAgent info fetching
  useEffect(() => {
    if (l1Wallet.account && isConnected && !eigenAgentInfo && !isLoadingEigenAgent) {
      fetchEigenAgentInfo();
    }
  }, [l1Wallet.account, isConnected]);

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