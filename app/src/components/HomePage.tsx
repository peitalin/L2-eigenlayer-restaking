import React, { useState, useEffect, useMemo } from 'react';
import { baseSepolia } from '../hooks/useClients';
import { formatEther, parseEther, Hex, Address, encodeAbiParameters } from 'viem';
import { getEigenAgentAndExecNonce } from '../utils/eigenlayerUtils';
import { signMessageForEigenAgentExecution } from '../utils/signers';
import { getRouterFeesL2 } from '../utils/routerFees';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { RECEIVER_CCIP_ADDRESS } from '../addresses/ethSepoliaContracts';
import { useClientsContext } from '../contexts/ClientsContext';

const HomePage: React.FC = () => {
  const {
    l1WalletClient,
    l2WalletClient,
    l1PublicClient,
    l2PublicClient,
    l1Account,
    l2Account,
    selectedChain,
    isConnected,
    switchChain,
    l1Balance,
    l2Balance,
    isLoadingBalance,
    refreshBalances
  } = useClientsContext();

  // State for EigenAgent info
  const [eigenAgentInfo, setEigenAgentInfo] = useState<{
    eigenAgentAddress: Address | null;
    execNonce: bigint;
  } | null>(null);
  const [isLoadingEigenAgent, setIsLoadingEigenAgent] = useState(false);

  // State for transaction details
  const [transactionAmount, setTransactionAmount] = useState<number>(0.11);
  const [expiryMinutes, setExpiryMinutes] = useState<number>(60);

  // State for signatures and transactions
  const [isCreatingSignature, setIsCreatingSignature] = useState(false);
  const [signature, setSignature] = useState<Hex | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isApprovingToken, setIsApprovingToken] = useState(false);
  const [approvalHash, setApprovalHash] = useState<string | null>(null);

  // Memoize the parsed amount to update whenever transactionAmount changes
  const amount = useMemo(() => {
    if (!transactionAmount) return parseEther("0");
    return parseEther(transactionAmount.toString());
  }, [transactionAmount]);

  // Fetch EigenAgent info on component mount or when account changes
  useEffect(() => {
    if (l1Account) {
      fetchEigenAgentInfo();
    }
  }, [l1Account]);

  // Add a second useEffect that will run once when the component mounts
  useEffect(() => {
    // Check if we already have the l1Account and still need to fetch eigenAgentInfo
    if (l1Account && !eigenAgentInfo) {
      fetchEigenAgentInfo();
    }
  }, []);

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

  // Fetch EigenAgent info from L1
  const fetchEigenAgentInfo = async () => {
    if (!l1Account) return;

    setIsLoadingEigenAgent(true);
    try {
      const info = await getEigenAgentAndExecNonce(l1Account);
      setEigenAgentInfo(info);

      if (!info.eigenAgentAddress) {
        setError("No EigenAgent found for this wallet address");
      }
    } catch (err) {
      console.error('Error checking EigenAgent:', err);
      setError(err instanceof Error ? err.message : 'Failed to check EigenAgent');
      setEigenAgentInfo(null);
    } finally {
      setIsLoadingEigenAgent(false);
    }
  };

  // Function to check token allowance
  const checkTokenAllowance = async (tokenAddress: Address, ownerAddress: Address, spenderAddress: Address): Promise<bigint> => {
    try {
      if (!l2PublicClient) {
        throw new Error("Public client not available for Base Sepolia");
      }

      const allowance = await l2PublicClient.readContract({
        address: tokenAddress,
        abi: [
          {
            name: "allowance",
            type: "function",
            stateMutability: "view",
            inputs: [
              { name: "owner", type: "address" },
              { name: "spender", type: "address" }
            ],
            outputs: [{ name: "", type: "uint256" }]
          }
        ],
        functionName: 'allowance',
        args: [ownerAddress, spenderAddress]
      });

      return allowance as bigint;
    } catch (error) {
      console.error('Error checking token allowance:', error);
      throw error;
    }
  };

  // Function to approve token spending
  const approveTokenSpending = async (tokenAddress: Address, spenderAddress: Address, amount: bigint): Promise<string> => {
    try {
      setIsApprovingToken(true);

      if (!l2WalletClient || !l2Account) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Check current allowance first
      const currentAllowance = await checkTokenAllowance(tokenAddress, l2Account, spenderAddress);

      // If allowance is already sufficient, return early
      if (currentAllowance >= amount) {
        console.log(`Allowance already sufficient: ${currentAllowance} >= ${amount}`);
        return "Allowance already sufficient";
      }

      // Send approval transaction
      const hash = await l2WalletClient.writeContract({
        address: tokenAddress,
        abi: [
          {
            name: "approve",
            type: "function",
            stateMutability: "nonpayable",
            inputs: [
              { name: "spender", type: "address" },
              { name: "amount", type: "uint256" }
            ],
            outputs: [{ name: "", type: "bool" }]
          }
        ],
        functionName: 'approve',
        args: [spenderAddress, amount],
        account: l2Account,
        chain: l2PublicClient.chain ?? baseSepolia,
      });

      setApprovalHash(hash);

      // Wait for transaction to be mined
      const receipt = await l2PublicClient.waitForTransactionReceipt({
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

  // Handle deposit into strategy
  const handleDepositIntoStrategy = async () => {
    // Ensure we have all required information
    if (!eigenAgentInfo?.eigenAgentAddress || !l1Account || !l2Account) {
      setError("EigenAgent information or wallet not connected");
      return;
    }
    if (!transactionAmount) {
      setError("Invalid transaction amount");
      return;
    }

    try {
      // Step 1: Approve token spending
      setIsCreatingSignature(false);

      try {
        setError(`Approving ${formatEther(amount)} tokens...`);
        await approveTokenSpending(
          CHAINLINK_CONSTANTS.baseSepolia.bridgeToken,
          SENDER_CCIP_ADDRESS,
          amount
        );
      } catch (approvalError) {
        setError(`Token approval failed: ${approvalError instanceof Error ? approvalError.message : 'Unknown error'}`);
        return;
      }

      // Step 2: Create signature with L1 client
      setError(null);
      setIsCreatingSignature(true);
      setSignature(null);

      // Temporarily switch to Ethereum Sepolia for signing
      setError("Temporarily switching to Ethereum Sepolia for signing...");
      await switchChain(l1PublicClient.chain?.id ?? 11155111);

      // Wait a moment for the switch to take effect
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Verify L1 client is available
      if (!l1WalletClient) {
        throw new Error("Wallet client not available for Sepolia");
      }

      // Create the deposit calldata
      const expiryTime = BigInt(Math.floor(Date.now()/1000) + expiryMinutes*60);
      // const expiryTime = BigInt(1742066222);

      // Sign the message
      const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
        l1WalletClient,
        l1Account,
        eigenAgentInfo.eigenAgentAddress,
        STRATEGY_MANAGER_ADDRESS,
        encodeDepositIntoStrategyMsg(
          STRATEGY,
          CHAINLINK_CONSTANTS.ethSepolia.bridgeToken,
          amount
        ),
        eigenAgentInfo.execNonce,
        expiryTime
      );

      setSignature(signature);

      // Switch back to Base Sepolia
      setError("Switching back to Base Sepolia...");
      await switchChain(l2PublicClient.chain?.id ?? 84532);

      // Wait for the switch to complete
      await new Promise(resolve => setTimeout(resolve, 1000));
      setError(null);

      // Dispatch the transaction
      await dispatchTransaction(messageWithSignature);
    } catch (err) {
      // Make sure we always switch back to Base Sepolia if there's an error
      try {
        await switchChain(l2PublicClient.chain?.id ?? 84532);
      } catch (switchBackError) {
        console.error('Error switching back to Base Sepolia:', switchBackError);
      }
      console.error('Error creating signature or dispatching transaction:', err);
      setError(err instanceof Error ? err.message : 'Failed to create signature or dispatch transaction');
    } finally {
      setIsCreatingSignature(false);
    }
  };

  // Function to dispatch CCIP transaction
  const dispatchTransaction = async (messageWithSignature: Hex) => {
    try {
      if (!window.ethereum) {
        throw new Error("Ethereum provider not available");
      }

      if (!l2WalletClient || !l2Account) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Function selector for sendMessagePayNative
      const functionSelector = '0x7132732a' as Hex;

      // Format token amounts for CCIP
      const formattedTokenAmounts = [
        [
          CHAINLINK_CONSTANTS.baseSepolia.bridgeToken as Address,
          amount
        ] as const
      ];

      // Get fee estimate
      const estimatedFee = await getRouterFeesL2(
        STRATEGY_MANAGER_ADDRESS,
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
          { type: 'bytes' }, // message
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

      // Send the transaction
      const hash = await l2WalletClient.sendTransaction({
        account: l2Account,
        to: SENDER_CCIP_ADDRESS,
        data: data,
        value: estimatedFee,
        chain: l2PublicClient.chain ?? baseSepolia,
      });

      alert(`Transaction sent! Hash: ${hash}\nView on BaseScan: https://sepolia.basescan.org/tx/${hash}`);

      // Wait for transaction to be mined
      const receipt = await l2PublicClient.waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        alert('Transaction successfully mined! Your deposit request has been sent to L1.');
      } else {
        throw new Error('Transaction failed on-chain');
      }
    } catch (error) {
      console.error('Error dispatching transaction:', error);
      setError(error instanceof Error ? error.message : 'Failed to dispatch transaction');
    }
  };

  return (
    <div className="home-page">
      <div className="page-layout">
        <div className="left-column">
          {l1Account ? (
            eigenAgentInfo && eigenAgentInfo.eigenAgentAddress ? (
              <div className="transaction-form">
                <h2>Deposit into Strategy</h2>

                <div className="account-balances">
                  <h3>Account Balances</h3>
                  <div className="balance-item">
                    <span className="balance-label">Ethereum Sepolia:</span>
                    <span className="balance-value">
                      {l1Balance ? `${formatEther(BigInt(l1Balance))} ETH` : 'Loading...'}
                    </span>
                  </div>
                  <div className="balance-item">
                    <span className="balance-label">Base Sepolia:</span>
                    <span className="balance-value">
                      {l2Balance ? `${formatEther(BigInt(l2Balance))} ETH` : 'Loading...'}
                    </span>
                    <button
                      onClick={refreshBalances}
                      disabled={isLoadingBalance}
                      className="refresh-balance-button"
                    >
                      {isLoadingBalance ? '...' : '⟳'}
                    </button>
                  </div>
                </div>

                <div className="form-group">
                  <label htmlFor="receiver">Target Address (Strategy Manager):</label>
                  <input
                    id="receiver"
                    type="text"
                    value={STRATEGY_MANAGER_ADDRESS}
                    onChange={() => {}}
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
            ) : (
              <div className="no-agent-warning">
                <h2>No EigenAgent Found</h2>
                <p>You need to create an EigenAgent on Ethereum Sepolia before you can deposit into a strategy.</p>
                <button
                  onClick={fetchEigenAgentInfo}
                  disabled={isLoadingEigenAgent}
                  className="eigenagent-check-button"
                >
                  {isLoadingEigenAgent ? 'Checking...' : 'Check Again'}
                </button>
              </div>
            )
          ) : (
            <div className="no-agent-warning">
              <h2>Wallet Connection Required</h2>
              <p>Please make sure your wallet is connected to both Ethereum Sepolia and Base Sepolia networks.</p>
            </div>
          )}
        </div>

        <div className="right-column">
          <div className="eigenagent-info">
            <h3>EigenAgent Information (Ethereum Sepolia)</h3>
            {!l1Account ? (
              <p>Connect your wallet to view EigenAgent information</p>
            ) : isLoadingEigenAgent ? (
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
                  onClick={fetchEigenAgentInfo}
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

          {/* Token Approval Status */}
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

      {error && (
        <div className="error-message">
          {error}
        </div>
      )}
    </div>
  );
};

export default HomePage;