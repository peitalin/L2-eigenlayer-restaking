import React, { createContext, useContext, ReactNode } from 'react';
import { useClients, ClientsState } from '../hooks/useClients';

// Create a context with a default empty value
const ClientsContext = createContext<ClientsState | null>(null);

interface ClientsProviderProps {
  children: ReactNode;
}

/**
 * Provider component that wraps app and makes client state available to any
 * child component that calls useClientsContext()
 */
export const ClientsProvider: React.FC<ClientsProviderProps> = ({ children }) => {
  const clientsState = useClients();

  return (
    <ClientsContext.Provider value={clientsState}>
      {children}
    </ClientsContext.Provider>
  );
};

/**
 * Hook for components to get the clients state
 * and re-render when it changes
 */
export const useClientsContext = (): ClientsState => {
  const context = useContext(ClientsContext);

  if (context === null) {
    throw new Error('useClientsContext must be used within a ClientsProvider');
  }

  return context;
};