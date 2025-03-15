import { useState, useEffect, useMemo } from 'react';
import { createWalletClient, createPublicClient, http, custom,
  formatEther, parseEther, type WalletClient, type PublicClient,
  defineChain, Chain, Address, Hex, encodeAbiParameters,
  toHex, toBytes, encodeFunctionData, getFunctionSelector, fromHex,
  stringToBytes,
  stringToHex,
  hexToString,
  encodePacked,
  fromBytes,
  bytesToString,
} from 'viem';
import { sepolia, base, mainnet } from 'viem/chains';
import { getEigenAgentAndExecNonce, checkAgentFactoryContract } from '../utils/eigenlayerUtils';
import { signMessageForEigenAgentExecution } from '../utils/signers';
import { getRouterFeesL1, getRouterFeesL2, formatFees } from '../utils/routerFees';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { EVMTokenAmount, senderCCIPAbi } from '../abis';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, ERC20_TOKEN_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { RECEIVER_CCIP_ADDRESS } from '../addresses/ethSepoliaContracts';

// Add this at the top of the file, after imports
declare global {
  interface Window {
    ethereum?: any;
  }
}

// Define Base Sepolia chain
const baseSepolia = defineChain({
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
const chains: { [key: string]: Chain } = {
  'ethereum-sepolia': sepolia,
  'base-sepolia': baseSepolia,
};

// Create public clients for balance checking
const publicClients: Record<number, PublicClient> = {
  [sepolia.id]: createPublicClient({
    chain: sepolia,
    transport: http('https://sepolia.gateway.tenderly.co')
  }),
  [baseSepolia.id]: createPublicClient({
    chain: baseSepolia,
    transport: http('https://base-sepolia.gateway.tenderly.co')
  })
};

// Add ERC20 ABI for token approval
const erc20Abi = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "spender",
        type: "address"
      },
      {
        name: "amount",
        type: "uint256"
      }
    ],
    outputs: [
      {
        name: "",
        type: "bool"
      }
    ]
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      {
        name: "owner",
        type: "address"
      },
      {
        name: "spender",
        type: "address"
      }
    ],
    outputs: [
      {
        name: "",
        type: "uint256"
      }
    ]
  }
];

const WalletConnect = () => {
  // Set default chain to Base Sepolia (L2)
  const [selectedChain, setSelectedChain] = useState<Chain>(baseSepolia);
  const [accounts, setAccounts] = useState<{[key: string]: string}>({});
  const [walletClients, setWalletClients] = useState<{[key: string]: WalletClient}>({});
  const [balances, setBalances] = useState<{[key: string]: string}>({});
  const [isConnecting, setIsConnecting] = useState(false);
  const [isLoadingBalance, setIsLoadingBalance] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [eigenAgentInfo, setEigenAgentInfo] = useState<{
    eigenAgentAddress: Address | null;
    execNonce: bigint;
  } | null>(null);
  const [isLoadingEigenAgent, setIsLoadingEigenAgent] = useState(false);
  const [isAgentFactoryValid, setIsAgentFactoryValid] = useState<boolean | null>(null);

  // New state for transaction details
  const [transactionAmount, setTransactionAmount] = useState<number>(0.11);
  const [expiryMinutes, setExpiryMinutes] = useState<number>(60);
  const [expiryTimestamp, setExpiryTimestamp] = useState<number>(Math.floor(Date.now()/1000) + 60*60);

  // Memoize the parsed amount to update whenever transactionAmount changes
  const amount = useMemo(() => {
    if (!transactionAmount) return parseEther("0");
    return parseEther(transactionAmount.toString());
  }, [transactionAmount]);

  // New state for signature process
  const [isCreatingSignature, setIsCreatingSignature] = useState(false);
  const [signature, setSignature] = useState<Hex | null>(null);
  const [messageWithSignature, setMessageWithSignature] = useState<Hex | null>(null);
  const [targetContractAddr, setTargetContractAddr] = useState<Address>('0x70997970C51812dc3A010C7d01b50e0d17dc79C8');

  // New state for fee estimation
  const [isEstimatingFee, setIsEstimatingFee] = useState(false);
  const [estimatedFee, setEstimatedFee] = useState<bigint | null>(null);
  const [formattedFee, setFormattedFee] = useState<string | null>(null);
  const [feeError, setFeeError] = useState<string | null>(null);

  // Add state for token approval
  const [isApprovingToken, setIsApprovingToken] = useState(false);
  const [approvalHash, setApprovalHash] = useState<string | null>(null);

  // Get if connected to current chain
  const isConnected = !!accounts[selectedChain.id];

  // Update balance whenever account or chain changes
  useEffect(() => {
    const fetchBalances = async () => {
      for (const [chainId, address] of Object.entries(accounts)) {
        await fetchBalance(Number(chainId), address);
      }
    };

    fetchBalances();
  }, [accounts]);

  // Prompt user to switch to Base Sepolia if they're on another network
  useEffect(() => {
    const promptForBaseSepolia = async () => {
      if (window.ethereum && isConnected && selectedChain.id !== baseSepolia.id) {
        try {
          await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${baseSepolia.id.toString(16)}` }],
          });
          setSelectedChain(baseSepolia);
        } catch (switchError: any) {
          // This error code indicates that the chain has not been added to MetaMask
          if (switchError.code === 4902) {
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
            } catch (addError) {
              console.error('Failed to add Base Sepolia network to wallet', addError);
            }
          } else {
            console.error('Failed to switch to Base Sepolia', switchError);
          }
        }
      }
    };

    promptForBaseSepolia();
  }, [isConnected, selectedChain.id]);

  // Fetch EigenAgent info regardless of which chain we're connected to
  useEffect(() => {
    if (isConnected) {
      // Even if connected to Base Sepolia, we still want to fetch EigenAgent info
      checkForEigenAgent();
    } else {
      setEigenAgentInfo(null);
    }
  }, [accounts]);

  // Update expiry timestamp when minutes change
  useEffect(() => {
    setExpiryTimestamp(Math.floor(Date.now()/1000) + expiryMinutes*60);
  }, [expiryMinutes]);


  const fetchBalance = async (chainId: number, address: string) => {
    setIsLoadingBalance(true);
    try {
      const publicClient = publicClients[chainId as keyof typeof publicClients];
      if (!publicClient) {
        throw new Error(`No public client for chain ${chainId}`);
      }

      const balance = await publicClient.getBalance({ address: address as Address });
      setBalances(prev => ({
        ...prev,
        [chainId]: formatEther(balance)
      }));
    } catch (err) {
      console.error(`Error fetching balance for chain ${chainId}:`, err);
    } finally {
      setIsLoadingBalance(false);
    }
  };

  const connectWallet = async (chain: Chain) => {
    setIsConnecting(true);
    setError(null);

    try {
      // Check if MetaMask is installed
      if (!window.ethereum) {
        throw new Error('No Ethereum wallet detected. Please install MetaMask or another wallet.');
      }

      // Create wallet client for this chain
      const client = createWalletClient({
        chain,
        transport: custom(window.ethereum)
      });

      // Request accounts
      const [address] = await client.requestAddresses();

      // Ensure we're on the right network (Base Sepolia)
      try {
        await window.ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: `0x${baseSepolia.id.toString(16)}` }],
        });

        // Set the chain to Base Sepolia
        setSelectedChain(baseSepolia);
      } catch (switchError: any) {
        // Handle chain not added to MetaMask
        if (switchError.code === 4902) {
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
          } catch (addError) {
            throw new Error('Failed to add Base Sepolia network to wallet');
          }
        } else {
          throw switchError;
        }
      }

      // Save clients and addresses for both L1 and L2
      // We connect to Base Sepolia but also track the same address on Ethereum Sepolia for L1 interactions
      setWalletClients(prev => ({
        ...prev,
        [baseSepolia.id]: client,
        [sepolia.id]: createWalletClient({
          chain: sepolia,
          transport: custom(window.ethereum)
        })
      }));

      // Use the same address for both chains
      setAccounts(prev => ({
        ...prev,
        [baseSepolia.id]: address,
        [sepolia.id]: address  // Track the same address on L1
      }));

      // Fetch initial balances for both chains
      await fetchBalance(baseSepolia.id, address);
      await fetchBalance(sepolia.id, address);

      // Fetch EigenAgent info from L1
      checkForEigenAgent();
    } catch (err) {
      console.error('Error connecting wallet:', err);
      setError(err instanceof Error ? err.message : 'Failed to connect wallet');
    } finally {
      setIsConnecting(false);
    }
  };

  const disconnectWallet = () => {
    // Disconnect from all chains
    setAccounts({});
    setBalances({});
    setEigenAgentInfo(null);
  };

  const formatBalance = (balance: string) => {
    // Format to 4 decimal places
    const balanceNum = parseFloat(balance);
    return balanceNum.toFixed(4);
  };

  const verifyAgentFactoryContract = async () => {
    try {
      const isValid = await checkAgentFactoryContract();
      setIsAgentFactoryValid(isValid);
      if (!isValid) {
        setError("The AgentFactory contract could not be found or accessed. Please check the contract address.");
      }
    } catch (err) {
      console.error('Error verifying AgentFactory contract:', err);
      setIsAgentFactoryValid(false);
    }
  };

  // Modified to always use Ethereum Sepolia for EigenAgent checks
  const checkForEigenAgent = async () => {
    if (!accounts[sepolia.id]) {
      // If we don't have the address for Sepolia, we can't check
      return;
    }

    setIsLoadingEigenAgent(true);
    try {
      // Verify the contract first (on L1)
      await verifyAgentFactoryContract();

      // Always use Ethereum Sepolia address for EigenAgent checks
      const info = await getEigenAgentAndExecNonce(accounts[sepolia.id] as Address);
      setEigenAgentInfo(info);

      if (info.eigenAgentAddress) {
        // Clear any previous errors if we found an agent
        setError(null);
      } else {
        // Only set error if we're explicitly checking (not on auto-check)
        // setError("No EigenAgent found for this wallet address");
      }
    } catch (err) {
      console.error('Error checking EigenAgent:', err);
      // Only set error if explicitly checking
      // setError(err instanceof Error ? err.message : 'Failed to check EigenAgent');
      setEigenAgentInfo(null);
    } finally {
      setIsLoadingEigenAgent(false);
    }
  };

  // Add a function to refresh all balances
  const refreshAllBalances = async () => {
    const chainIds = Object.keys(accounts);
    setIsLoadingBalance(true);

    try {
      const promises = chainIds.map(chainId =>
        fetchBalance(Number(chainId), accounts[chainId])
      );

      await Promise.all(promises);
    } catch (err) {
      console.error('Error refreshing all balances:', err);
    } finally {
      setIsLoadingBalance(false);
    }
  };

  // Format the expiry date for display
  const formatExpiryDate = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs
    if (value === '' || /^\d*\.?\d*$/.test(value)) {
      const numValue = value === '' ? 0 : parseFloat(value);
      setTransactionAmount(numValue);
    }
  };

  // Handle expiry minutes changes
  const handleExpiryChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseInt(e.target.value);
    if (!isNaN(value) && value > 0) {
      setExpiryMinutes(value);
    }
  };

  // Handle receiver address changes
  const handleTargetContractAddressChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    if (/^0x[a-fA-F0-9]{0,40}$/.test(value)) {
      setTargetContractAddr(value as Address);
    }
  };

  // Add function to check token allowance
  const checkTokenAllowance = async (tokenAddress: Address, ownerAddress: Address, spenderAddress: Address): Promise<bigint> => {
    try {
      const publicClient = publicClients[baseSepolia.id];
      if (!publicClient) {
        throw new Error("Public client not available for Base Sepolia");
      }

      const allowance = await publicClient.readContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: 'allowance',
        args: [ownerAddress, spenderAddress]
      });

      return allowance as bigint;
    } catch (error) {
      console.error('Error checking token allowance:', error);
      throw error;
    }
  };

  // Add function to approve token spending
  const approveTokenSpending = async (tokenAddress: Address, spenderAddress: Address, amount: bigint): Promise<string> => {
    try {
      setIsApprovingToken(true);

      // Get the wallet client for Base Sepolia
      const client = walletClients[baseSepolia.id];
      if (!client) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Check current allowance first
      const userAddress = accounts[baseSepolia.id] as Address;
      const currentAllowance = await checkTokenAllowance(tokenAddress, userAddress, spenderAddress);

      // If allowance is already sufficient, return early
      if (currentAllowance >= amount) {
        console.log(`Allowance already sufficient: ${currentAllowance} >= ${amount}`);
        return "Allowance already sufficient";
      }

      // Send approval transaction
      const hash = await client.writeContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: 'approve',
        args: [spenderAddress, amount],
        account: userAddress,
        chain: baseSepolia
      });

      setApprovalHash(hash);

      // Wait for transaction to be mined
      const receipt = await publicClients[baseSepolia.id].waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        console.log(`Token approval successful: ${hash}`);
        return hash;
      } else {
        throw new Error('Token approval transaction failed on-chain');
      }
    } catch (error) {
      console.error('Error approving token spending:', error);
      throw error;
    } finally {
      setIsApprovingToken(false);
    }
  };

  // Modify handleDepositIntoStrategy to handle single tokenAmount
  const handleDepositIntoStrategy = async () => {
    // Ensure we have all required information
    if (!eigenAgentInfo?.eigenAgentAddress || !accounts[sepolia.id]) {
      setError("EigenAgent information or wallet not connected");
      return;
    }
    if (!transactionAmount) {
      setError("Invalid transaction amount");
      return;
    }

    // No need to calculate amount here, we use the memoized value

    try {
      // Check if we need to approve token spending first
      // Only for non-native tokens (if token address is not zero address)
      setIsCreatingSignature(false);

      try {
        // Show approval status to user
        setError(`Approving ${formatEther(amount)} tokens...`);

        // Approve token spending
        await approveTokenSpending(
          CHAINLINK_CONSTANTS.baseSepolia.bridgeToken,
          SENDER_CCIP_ADDRESS, // The contract that will spend the tokens
          amount
        );
      } catch (approvalError) {
        setError(`Token approval failed: ${approvalError instanceof Error ? approvalError.message : 'Unknown error'}`);
        return;
      }

      // Clear approval message
      setError(null);
      // Continue with signature creation
      setIsCreatingSignature(true);
      setSignature(null);

      // Request the connected wallet to sign the message
      const client = walletClients[sepolia.id];

      if (!client) {
        throw new Error("Wallet client not available for Sepolia");
      }

      // Get the account address
      const userAddress = accounts[sepolia.id] as Address;
      // Get the current timestamp + expiry minutes for the expiry time
      const expiryTime = BigInt(Math.floor(Date.now()/1000) + expiryMinutes*60);
      // Use encodeDepositIntoStrategyMsg to create the calldata for the strategy deposit
      console.log("depositIntoStrategy amount: ", amount);
      console.log("depositIntoStrategy token: ", CHAINLINK_CONSTANTS.ethSepolia.bridgeToken);
      const depositCalldata = encodeDepositIntoStrategyMsg(
        STRATEGY, // The strategy address from eigenlayerContracts
        CHAINLINK_CONSTANTS.ethSepolia.bridgeToken, // The L1 token address from eigenlayerContracts
        amount
      );

      // Use signMessageForEigenAgentExecution with Base Sepolia (L2) chain ID
      const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
        client,
        userAddress,
        eigenAgentInfo.eigenAgentAddress,
        baseSepolia.id, // Use Base Sepolia chain ID (L2)
        STRATEGY_MANAGER_ADDRESS, // Use the strategy manager as the target contract
        depositCalldata,  // Use the encoded deposit function call
        eigenAgentInfo.execNonce,
        expiryTime
      );

      setSignature(signature);

      // Dispatch the transaction with messageWithSignature as calldata
      await dispatchTransaction(messageWithSignature);

    } catch (err) {
      console.error('Error creating signature or dispatching transaction:', err);
      setError(err instanceof Error ? err.message : 'Failed to create signature or dispatch transaction');
    } finally {
      setIsCreatingSignature(false);
    }
  };

  // New function to handle transaction dispatch using viem
  const dispatchTransaction = async (messageWithSignature: Hex) => {
    try {

      if (!window.ethereum) {
        throw new Error("Ethereum provider not available");
      }

      // Get the wallet client for Base Sepolia
      const client = walletClients[baseSepolia.id];
      if (!client) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Encode the function call manually
      // const functionSelector = getFunctionSelector('sendMessagePayNative(uint64,address,string,tuple[],uint256)');
      const functionSelector = '0x7132732a' as Hex;

      // No need to calculate amount here, we use the memoized value

      // Format token amount for ABI encoding - ensure correct token on correct chain
      const formattedTokenAmounts = [
        [
          CHAINLINK_CONSTANTS.baseSepolia.bridgeToken as Address,
          amount
        ] as const
      ]

      console.log("formattedTokensAmounts:", formattedTokenAmounts);
      console.log("messageWithSignature: ", messageWithSignature);
      console.log("toHex(messageWithSignature): ", toHex(messageWithSignature));

      const estimatedFee = await getRouterFeesL2(
        targetContractAddr,
        messageWithSignature,
        [{
          token: CHAINLINK_CONSTANTS.baseSepolia.bridgeToken as Address,
          amount: amount
        }],
        BigInt(860_000) // gasLimit
      );

      // Encode the function parameters
      const encodedParams = encodeAbiParameters(
        [
          { type: 'uint64' }, // destinationChainSelector
          { type: 'address' }, // receiverContract
          { type: 'bytes' }, // message in bytes, not string. Viem tries to encode string as hex twice
          { type: 'tuple[]', components: [
            { type: 'address' }, // token
            { type: 'uint256' } // amount
          ]},
          { type: 'uint256' } // gasLimit
        ],
        [
          BigInt(CHAINLINK_CONSTANTS.ethSepolia.chainSelector),
          RECEIVER_CCIP_ADDRESS,
          messageWithSignature,
          formattedTokenAmounts,
          BigInt(860_000) // gasLimit
        ]
      );

      // Combine the function selector with the encoded parameters
      const data: Hex = `0x${functionSelector.slice(2)}${encodedParams.slice(2)}`;
      console.log("estimatedFee: ", estimatedFee);
      console.log("calldata:", data);

      // Use sendTransaction directly
      const hash = await client.sendTransaction({
        account: accounts[baseSepolia.id] as Address,
        chain: baseSepolia,
        to: SENDER_CCIP_ADDRESS,
        data: data as Hex,
        value: estimatedFee,
      });

      alert(`Transaction sent! Hash: ${hash}\nView on BaseScan: https://sepolia.basescan.org/tx/${hash}`);

      // Wait for transaction to be mined
      const receipt = await publicClients[baseSepolia.id].waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        alert('Transaction successfully mined! Your deposit request has been sent to L1.');
      } else {
        throw new Error('Transaction failed on-chain');
      }

      // Refresh balances after transaction
      await refreshAllBalances();

    } catch (error) {
      console.error('Error dispatching transaction:', error);
      setError(error instanceof Error ? error.message : 'Failed to dispatch transaction');
    }
  };


  return (
    <div className="wallet-connect">
      <h1>EigenLayer L2 Restaking</h1>
      {isConnected && (
        <div className="wallet-navbar">
          <div className="navbar-info">
            <div className="navbar-section">
              <span className="section-label">Current Chain:</span>
              <span className="section-value">{selectedChain.name}</span>
            </div>

            <div className="navbar-section">
              <span className="section-label">Connected Wallet:</span>
              <span className="section-value wallet-address-short">
                {accounts[selectedChain.id]?.substring(0, 6)}...{accounts[selectedChain.id]?.substring(38)}
              </span>
            </div>
          </div>

          <button
            onClick={disconnectWallet}
            className="disconnect-button"
          >
            Disconnect
          </button>
        </div>
      )}

      {isConnected && (
        <div className="page-layout">
          <div className="left-column">
            <div className="wallet-summary">
              <div className="summary-section">
                <div className="connections-header">
                  <h3>Balances</h3>
                  <button
                    onClick={refreshAllBalances}
                    className="refresh-button"
                    disabled={isLoadingBalance}
                  >
                    ↻
                  </button>
                </div>
                <div className="connections-summary">
                  {Object.entries(accounts).map(([chainId, _]) => {
                    const chain = Object.values(chains).find(c => c.id === Number(chainId));
                    const chainBalance = balances[chainId];

                    return (
                      <div key={chainId} className="chain-connection">
                        <div className="chain-name">{chain?.name || chainId}</div>
                        <div className="chain-balance">
                          {chainBalance ? `${formatBalance(chainBalance)} ETH` : 'Loading...'}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            {eigenAgentInfo && eigenAgentInfo.eigenAgentAddress && (
              <div className="transaction-form">

                <div className="form-group">
                  <label htmlFor="receiver">Strategy Address:</label>
                  <input
                    id="receiver"
                    type="text"
                    value={targetContractAddr}
                    onChange={handleTargetContractAddressChange}
                    className="receiver-input"
                    placeholder="0x..."
                    disabled={true}
                  />
                  <div className="input-note">Using CCIP Strategy from EigenLayer contracts</div>
                </div>

                <div className="form-group">
                  <label htmlFor="amount">Token Amount:</label>
                  <input
                    id="amount"
                    type="text"
                    value={transactionAmount === 0 ? '' : transactionAmount.toString()}
                    onChange={handleAmountChange}
                    className="amount-input"
                    placeholder="0.11"
                  />
                  <div className="input-note">Using EigenLayer TokenERC20</div>
                </div>

                <div className="form-group">
                  <label htmlFor="expiry">Expiry (minutes from now):</label>
                  <input
                    id="expiry"
                    type="number"
                    min="1"
                    value={expiryMinutes}
                    onChange={handleExpiryChange}
                    className="expiry-input"
                  />
                </div>

                <button
                  className="create-transaction-button"
                  disabled={isCreatingSignature}
                  onClick={handleDepositIntoStrategy}
                >
                  {isCreatingSignature ? 'Creating Signature...' : 'Sign Strategy Deposit'}
                </button>

              </div>
            )}
          </div>

          <div className="right-column">
            <div className="eigenagent-info">
              <h3>EigenAgent Information (Ethereum Sepolia)</h3>
              {isLoadingEigenAgent ? (
                <p>Loading EigenAgent info...</p>
              ) : eigenAgentInfo ? (
                <div>
                  {eigenAgentInfo.eigenAgentAddress ? (
                    <>
                      <div className="eigenagent-address">
                        <strong>EigenAgent Address:</strong> {eigenAgentInfo.eigenAgentAddress}
                      </div>
                      <div className="execution-nonce">
                        <strong>Execution Nonce:</strong> {eigenAgentInfo.execNonce.toString()}
                      </div>
                    </>
                  ) : (
                    <p>No EigenAgent found for this wallet</p>
                  )}
                  <button
                    onClick={checkForEigenAgent}
                    className="eigenagent-check-button"
                    disabled={isLoadingEigenAgent}
                  >
                    Refresh EigenAgent Info
                  </button>
                </div>
              ) : (
                <p>Failed to load EigenAgent information</p>
              )}
            </div>

            {/* Add approval status display */}
            {isApprovingToken && (
              <div className="approval-status">
                <h3>Token Approval Status</h3>
                <p>Approving token for spending...</p>
                {approvalHash && (
                  <p>
                    Approval Transaction:
                    <a
                      href={`https://sepolia.basescan.org/tx/${approvalHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      {approvalHash.substring(0, 10)}...
                    </a>
                  </p>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {!isConnected && (
        <button
          onClick={() => connectWallet(baseSepolia)}
          disabled={isConnecting}
          className="connect-button"
        >
          {isConnecting ? 'Connecting...' : `Connect to ${baseSepolia.name}`}
        </button>
      )}

      {error && (
        <div className="error-message">
          {error}
        </div>
      )}
    </div>
  );
};

export default WalletConnect;

// Update styles for the fee-display component to have a dark theme
const styles = `
.input-note {
  font-size: 0.8rem;
  color: #777;
  margin-top: 4px;
  font-style: italic;
}

.info-box {
  margin: 15px 0;
  padding: 12px;
  background-color: #e7f5fe;
  border-left: 4px solid #0088cc;
  border-radius: 3px;
}

.info-box h4 {
  margin-top: 0;
  margin-bottom: 8px;
  color: #0088cc;
}

.info-box p {
  margin: 8px 0;
  font-size: 0.9rem;
}

.fee-display {
  margin: 15px 0;
  padding: 10px;
  background-color: #333;
  border-radius: 5px;
  color: #fff;
}

.fee-amount {
  font-size: 1.2rem;
  font-weight: bold;
  margin: 5px 0;
  color: #2a9d8f;
}

.fee-error {
  font-size: 1rem;
  margin: 5px 0;
  color: #e63946;
}

.refresh-fee-button {
  margin-top: 5px;
  padding: 5px 10px;
  background-color: #007bff;
  border: none;
  border-radius: 3px;
  color: #fff;
  cursor: pointer;
}

.refresh-fee-button:hover {
  background-color: #0056b3;
}

.refresh-fee-button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  background-color: #004085;
}

.loading-indicator {
  font-style: italic;
  color: #bbb;
}

.approval-status {
  margin-top: 20px;
  padding: 15px;
  background-color: #333;
  border-left: 4px solid #17a2b8;
  border-radius: 5px;
  color: #fff;
}

.approval-status h3 {
  margin-top: 0;
  color: #17a2b8;
}

.approval-status a {
  color: #4dabf7;
  text-decoration: none;
  margin-left: 5px;
}

.approval-status a:hover {
  text-decoration: underline;
  color: #74c0fc;
}
`;

// Add the styles to the document
if (typeof document !== 'undefined') {
  const styleElement = document.createElement('style');
  styleElement.innerHTML = styles;
  document.head.appendChild(styleElement);
}
