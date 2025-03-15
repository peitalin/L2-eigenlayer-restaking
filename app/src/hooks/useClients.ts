import { useState, useEffect, useCallback } from 'react';
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
    transport: http('https://sepolia.gateway.tenderly.co')
  }),
  [baseSepolia.id]: createPublicClient({
    chain: baseSepolia,
    transport: http('https://base-sepolia.gateway.tenderly.co')
  })
};

export interface ClientsState {
  l1WalletClient: WalletClient | null;
  l2WalletClient: WalletClient | null;
  l1PublicClient: PublicClient;
  l2PublicClient: PublicClient;
  l1Account: Address | null;
  l2Account: Address | null;
  selectedChain: Chain;
  isConnected: boolean;
  connect: () => Promise<void>;
  disconnect: () => void;
  switchChain: (chainId: number) => Promise<void>;
  l1Balance: string | null;
  l2Balance: string | null;
  isLoadingBalance: boolean;
  refreshBalances: () => Promise<void>;
}

/**
 * Hook that provides wallet and public clients for L1 (Ethereum Sepolia) and L2 (Base Sepolia)
 */
export function useClients(): ClientsState {
  const [l1WalletClient, setL1WalletClient] = useState<WalletClient | null>(null);
  const [l2WalletClient, setL2WalletClient] = useState<WalletClient | null>(null);
  const [l1Account, setL1Account] = useState<Address | null>(null);
  const [l2Account, setL2Account] = useState<Address | null>(null);
  const [selectedChain, setSelectedChain] = useState<Chain>(baseSepolia);
  const [l1Balance, setL1Balance] = useState<string | null>(null);
  const [l2Balance, setL2Balance] = useState<string | null>(null);
  const [isLoadingBalance, setIsLoadingBalance] = useState(false);

  const isConnected = !!l2Account;

  // Function to fetch balances
  const fetchBalances = useCallback(async () => {
    setIsLoadingBalance(true);
    try {
      if (l1Account) {
        const balance = await publicClients[sepolia.id].getBalance({ address: l1Account });
        setL1Balance(balance.toString());
      }

      if (l2Account) {
        const balance = await publicClients[baseSepolia.id].getBalance({ address: l2Account });
        setL2Balance(balance.toString());
      }
    } catch (error) {
      console.error('Error fetching balances:', error);
    } finally {
      setIsLoadingBalance(false);
    }
  }, [l1Account, l2Account]);

  // Fetch balances when accounts change
  useEffect(() => {
    if (l1Account || l2Account) {
      fetchBalances();
    } else {
      setL1Balance(null);
      setL2Balance(null);
    }
  }, [l1Account, l2Account, fetchBalances]);

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

      // Set the clients and accounts
      setL1WalletClient(sepoliaClient);
      setL2WalletClient(baseClient);
      setL1Account(address);
      setL2Account(address);
      setSelectedChain(baseSepolia);
    } catch (error) {
      console.error('Error connecting wallet:', error);
      throw error;
    }
  };

  // Disconnect wallet
  const disconnect = () => {
    setL1WalletClient(null);
    setL2WalletClient(null);
    setL1Account(null);
    setL2Account(null);
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
    l1WalletClient,
    l2WalletClient,
    l1PublicClient: publicClients[sepolia.id],
    l2PublicClient: publicClients[baseSepolia.id],
    l1Account,
    l2Account,
    selectedChain,
    isConnected,
    connect,
    disconnect,
    switchChain,
    l1Balance,
    l2Balance,
    isLoadingBalance,
    refreshBalances: fetchBalances
  };
}