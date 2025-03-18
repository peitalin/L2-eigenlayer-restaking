import { useState, useEffect, useCallback, useRef } from 'react';
import {
  createWalletClient, createPublicClient, http, custom,
  type WalletClient, type PublicClient,
  Chain, Address, defineChain
} from 'viem';
import { sepolia } from 'viem/chains';

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
      http: ['https://base-sepolia.gateway.tenderly.co'],
    },
    public: {
      http: ['https://base-sepolia.gateway.tenderly.co'],
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
    transport: http('https://sepolia.gateway.tenderly.co', {
      // Add reasonable batching
      batch: true,
      fetchOptions: {
        cache: 'force-cache'
      }
    })
  }),
  [baseSepolia.id]: createPublicClient({
    chain: baseSepolia,
    transport: http('https://base-sepolia.gateway.tenderly.co', {
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

  // Connect to wallet and initialize clients
  const connect = async () => {
    try {
      // Check if MetaMask is installed
      if (!window.ethereum) {
        throw new Error('No Ethereum wallet detected. Please install MetaMask or another wallet.');
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

      // Request accounts
      const [address] = await baseClient.requestAddresses();

      // Switch to Base Sepolia
      await switchChain(baseSepolia.id);

      // Update L1 and L2 wallet states
      setL1Wallet({
        client: sepoliaClient,
        account: address,
        balance: null,
        publicClient: publicClients[sepolia.id]
      });

      setL2Wallet({
        client: baseClient,
        account: address,
        balance: null,
        publicClient: publicClients[baseSepolia.id]
      });

      setSelectedChain(baseSepolia);
    } catch (error) {
      console.error('Error connecting wallet:', error);
      throw error;
    }
  };

  // Disconnect wallet
  const disconnect = () => {
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
      // This error code indicates that the chain has not been added to MetaMask
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