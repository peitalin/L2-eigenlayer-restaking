import { useState, useEffect, useCallback, useRef } from 'react';
import {
  createWalletClient, createPublicClient, http, custom,
  type WalletClient, type PublicClient,
  Chain, Address, defineChain
} from 'viem';
import { sepolia } from 'viem/chains';

const BASE_SEPOLIA_RPC_URL = 'https://base-sepolia.gateway.tenderly.co';
// const BASE_SEPOLIA_RPC_URL = 'https://base-sepolia-rpc.publicnode.com'
// const BASE_SEPOLIA_RPC_URL = 'https://base-sepolia.drpc.org';
const ETH_SEPOLIA_RPC_URL = 'https://sepolia.gateway.tenderly.co';

// Constants for localStorage
const WALLET_CONNECTED_KEY = 'eigenLayerWalletConnected';

// Define Base Sepolia chain
export const baseSepolia = defineChain({
  id: 84_532,
  name: 'Base Sepolia',
  network: 'base-sepolia',
  nativeCurrency: {
    decimals: 18,
    name: 'Sepolia Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: {
      http: [BASE_SEPOLIA_RPC_URL]
    },
    public: {
      http: [BASE_SEPOLIA_RPC_URL]
    },
  },
  blockExplorers: {
    default: {
      name: 'BaseScan',
      url: 'https://sepolia.basescan.org',
    },
  },
  testnet: true,
});

// Available chains in our app
export const chains: { [key: string]: Chain } = {
  'ethereum-sepolia': sepolia,
  'base-sepolia': baseSepolia,
};

// Create public clients for each chain
export const publicClients: Record<number, PublicClient> = {
  [sepolia.id]: createPublicClient({
    chain: sepolia,
    transport: http(ETH_SEPOLIA_RPC_URL, {
      // Add reasonable batching
      batch: true,
      fetchOptions: {
        cache: 'force-cache'
      }
    })
  }),
  [baseSepolia.id]: createPublicClient({
    chain: baseSepolia,
    transport: http(BASE_SEPOLIA_RPC_URL, {
      // Add reasonable batching
      batch: true,
      fetchOptions: {
        cache: 'force-cache'
      }
    })
  })
};

// Interface for wallet state
export interface WalletState {
  client: WalletClient | null;
  account: Address | null;
  balance: string | null;
  publicClient: PublicClient;
}

export interface ClientsState {
  l1Wallet: WalletState;
  l2Wallet: WalletState;
  selectedChain: Chain;
  isConnected: boolean;
  connect: () => Promise<void>;
  disconnect: () => void;
  switchChain: (chainId: number) => Promise<void>;
  isLoadingBalance: boolean;
  refreshBalances: () => Promise<void>;
}

/**
 * Hook that provides wallet and public clients for L1 (Ethereum Sepolia) and L2 (Base Sepolia)
 */
export function useClients(): ClientsState {
  // Consolidated L1 wallet state (Ethereum Sepolia)
  const [l1Wallet, setL1Wallet] = useState<WalletState>({
    client: null,
    account: null,
    balance: null,
    publicClient: publicClients[sepolia.id]
  });

  // Consolidated L2 wallet state (Base Sepolia)
  const [l2Wallet, setL2Wallet] = useState<WalletState>({
    client: null,
    account: null,
    balance: null,
    publicClient: publicClients[baseSepolia.id]
  });

  const [selectedChain, setSelectedChain] = useState<Chain>(baseSepolia);
  const [isLoadingBalance, setIsLoadingBalance] = useState(false);

  const isConnected = !!l2Wallet.account;

  // Add a ref to track last balance fetch time
  const lastBalanceFetchRef = useRef<number>(0);

  // Function to fetch balances
  const fetchBalances = useCallback(async () => {
    // Skip if already loading or if we've fetched within the last 30 seconds
    if (isLoadingBalance || Date.now() - lastBalanceFetchRef.current < 30000) {
      console.log('Skipping balance fetch (throttled)');
      return;
    }

    setIsLoadingBalance(true);
    lastBalanceFetchRef.current = Date.now();

    try {
      // Only fetch balances if we actually have an account
      if (l1Wallet.account) {
        const balance = await l1Wallet.publicClient.getBalance({ address: l1Wallet.account });
        setL1Wallet(prev => ({
          ...prev,
          balance: balance.toString()
        }));
      }

      if (l2Wallet.account) {
        const balance = await l2Wallet.publicClient.getBalance({ address: l2Wallet.account });
        setL2Wallet(prev => ({
          ...prev,
          balance: balance.toString()
        }));
      }
    } catch (error) {
      console.error('Error fetching balances:', error);
    } finally {
      setIsLoadingBalance(false);
    }
  }, [l1Wallet.account, l2Wallet.account, l1Wallet.publicClient, l2Wallet.publicClient, isLoadingBalance]);

  // Fetch balances when accounts change
  useEffect(() => {
    if (l1Wallet.account || l2Wallet.account) {
      fetchBalances();
    } else {
      setL1Wallet(prev => ({ ...prev, balance: null }));
      setL2Wallet(prev => ({ ...prev, balance: null }));
    }
  }, [l1Wallet.account, l2Wallet.account, fetchBalances]);

  // Try to auto-connect on initial load
  useEffect(() => {
    const isWalletPreviouslyConnected = localStorage.getItem(WALLET_CONNECTED_KEY) === 'true';

    if (isWalletPreviouslyConnected && !isConnected && window.ethereum) {
      console.log('Auto-connecting previously connected wallet...');
      connect().catch(err => {
        console.error('Failed to auto-connect wallet:', err);
        // Remove the stored value if auto-connect fails
        localStorage.removeItem(WALLET_CONNECTED_KEY);
      });
    }
  }, []);

  // Disconnect wallet
  const disconnect = async () => {
    try {
      // Try to detect different wallet providers
      if ((window as any).rabby && !window.ethereum) {
        window.ethereum = (window as any).rabby;
      }

      // Clear wallet states first to ensure UI updates immediately
      setL1Wallet(prev => ({
        ...prev,
        client: null,
        account: null,
        balance: null
      }));

      setL2Wallet(prev => ({
        ...prev,
        client: null,
        account: null,
        balance: null
      }));

      // Remove connection state from localStorage
      localStorage.removeItem(WALLET_CONNECTED_KEY);

      // Reset selected chain to Base Sepolia
      setSelectedChain(baseSepolia);

      if (window.ethereum) {
        try {
          // Just clear the accounts - this is more reliable than permissions
          await window.ethereum.request({
            method: 'eth_accounts'
          });
        } catch (e) {
          console.error('Error clearing accounts:', e);
        }
      }
    } catch (error) {
      console.error('Error disconnecting wallet:', error);
    }
  };

  // Connect to wallet and initialize clients
  const connect = async () => {
    try {
      // Try to detect different wallet providers
      if ((window as any).rabby && !window.ethereum) {
        window.ethereum = (window as any).rabby;
      }

      // Check if any provider is available
      if (!window.ethereum) {
        throw new Error('No Ethereum wallet detected. Please install MetaMask, Rabby, or another wallet.');
      }

      // Create wallet clients for both chains
      const baseClient = createWalletClient({
        chain: baseSepolia,
        transport: custom(window.ethereum)
      });

      const sepoliaClient = createWalletClient({
        chain: sepolia,
        transport: custom(window.ethereum)
      });

      // Request accounts only if we don't have one
      let address;
      const accounts = await window.ethereum.request({ method: 'eth_accounts' });
      if (accounts.length === 0) {
        [address] = await window.ethereum.request({
          method: 'eth_requestAccounts'
        });
      } else {
        address = accounts[0];
      }

      // Update L1 and L2 wallet states first
      setL1Wallet({
        client: sepoliaClient,
        account: address as Address,
        balance: null,
        publicClient: publicClients[sepolia.id]
      });

      setL2Wallet({
        client: baseClient,
        account: address as Address,
        balance: null,
        publicClient: publicClients[baseSepolia.id]
      });

      // Store connection state in localStorage
      localStorage.setItem(WALLET_CONNECTED_KEY, 'true');

      // Switch to Base Sepolia last
      await switchChain(baseSepolia.id);
    } catch (error) {
      console.error('Error connecting wallet:', error);
      throw error;
    }
  };

  // Switch the active chain
  const switchChain = async (chainId: number) => {
    try {
      if (!window.ethereum) return;

      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: `0x${chainId.toString(16)}` }],
      });

      const chainConfig = Object.values(chains).find(c => c.id === chainId);
      if (chainConfig) {
        setSelectedChain(chainConfig);
      }
    } catch (error: any) {
      // This error code indicates that the chain has not been added to the wallet
      if (error.code === 4902 && chainId === baseSepolia.id) {
        try {
          await window.ethereum.request({
            method: 'wallet_addEthereumChain',
            params: [
              {
                chainId: `0x${baseSepolia.id.toString(16)}`,
                chainName: baseSepolia.name,
                nativeCurrency: baseSepolia.nativeCurrency,
                rpcUrls: [baseSepolia.rpcUrls.default.http[0]],
                blockExplorerUrls: baseSepolia.blockExplorers?.default ? [baseSepolia.blockExplorers.default.url] : undefined,
              },
            ],
          });

          // After adding, try to switch again
          await switchChain(chainId);
        } catch (addError) {
          console.error('Failed to add Base Sepolia network to wallet', addError);
          throw addError;
        }
      } else {
        console.error('Failed to switch chain', error);
        throw error;
      }
    }
  };

  // Listen for accountsChanged event from wallet
  useEffect(() => {
    if (!window.ethereum) return;

    const handleAccountsChanged = async (accounts: string[]) => {
      console.log('Accounts changed:', accounts);

      if (accounts.length === 0) {
        // Just disconnect if all accounts are removed
        await disconnect();
        return;
      }

      try {
        // Create new wallet clients for both chains
        const baseClient = createWalletClient({
          chain: baseSepolia,
          transport: custom(window.ethereum)
        });

        const sepoliaClient = createWalletClient({
          chain: sepolia,
          transport: custom(window.ethereum)
        });

        // Update wallet states with new account
        const address = accounts[0] as Address;
        setL1Wallet(prev => ({
          ...prev,
          client: sepoliaClient,
          account: address,
          balance: null
        }));

        setL2Wallet(prev => ({
          ...prev,
          client: baseClient,
          account: address,
          balance: null
        }));

        // Just refresh balances - don't switch chains
        await fetchBalances();

      } catch (error) {
        console.error('Error handling account change:', error);
        await disconnect();
      }
    };

    // Add event listener
    window.ethereum.on('accountsChanged', handleAccountsChanged);

    // Clean up the event listener when component unmounts
    return () => {
      if (window.ethereum?.removeListener) {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
      }
    };
  }, [disconnect, fetchBalances]);

  // Listen for chainChanged event from wallet
  useEffect(() => {
    // Try to detect different wallet providers
    if ((window as any).rabby && !window.ethereum) {
      window.ethereum = (window as any).rabby;
    }

    if (!window.ethereum) return;

    const handleChainChanged = (chainIdHex: string) => {

      // Convert hex chainId to number
      const chainId = parseInt(chainIdHex, 16);

      // Find matching chain configuration
      const chainConfig = Object.values(chains).find(c => c.id === chainId);

      if (chainConfig) {
        setSelectedChain(chainConfig);

        // Refresh balances after chain switch
        fetchBalances();
      }
    };

    window.ethereum.on('chainChanged', handleChainChanged);

    // Clean up the event listener when component unmounts
    return () => {
      window.ethereum.removeListener('chainChanged', handleChainChanged);
    };
  }, [fetchBalances]);

  return {
    l1Wallet,
    l2Wallet,
    selectedChain,
    isConnected,
    connect,
    disconnect,
    switchChain,
    isLoadingBalance,
    refreshBalances: fetchBalances
  };
}