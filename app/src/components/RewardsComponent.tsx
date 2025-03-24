import React, { useState, useEffect } from 'react';
import { Address, formatEther } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { encodeProcessClaimMsg } from '../utils/encoders';
import { simulateRewardClaim } from '../utils/rewards';
import { RewardsMerkleClaim } from '../abis/RewardsCoordinatorTypes';
import { RewardsCoordinatorABI } from '../abis';
import { useToast } from '../utils/toast';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import {
  getRewardsProofData,
  createRewardClaim
} from '../utils/rewardsMock';
import {
  REWARDS_COORDINATOR_ADDRESS,
} from '../addresses';
import {
  BaseSepolia,
  EthSepolia
} from '../addresses';
import { APP_CONFIG } from '../configs';

const RewardsComponent: React.FC = () => {
  const {
    l1Wallet,
    isConnected,
    eigenAgentInfo,
    isLoadingEigenAgent
  } = useClientsContext();
  const { showToast } = useToast();
  const { addTransaction } = useTransactionHistory();

  const [currentDistRootIndex, setCurrentDistRootIndex] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [simulationResult, setSimulationResult] = useState<boolean | null>(null);
  const [rewardAmount, setRewardAmount] = useState<bigint>(0n);
  const [rewardToken, setRewardToken] = useState<Address | null>(null);

  // Set up the EigenLayer operation hook
  const {
    isExecuting,
    signature,
    error: operationError,
    info: operationInfo,
    executeWithMessage
  } = useEigenLayerOperation({
    targetContractAddr: REWARDS_COORDINATOR_ADDRESS,
    amount: 0n, // No value to send with the transaction
    customGasLimit: APP_CONFIG.GAS_LIMITS.CLAIM_REWARDS,
    onSuccess: (txHash, receipt, execNonce) => {
      showToast('Rewards claim transaction submitted!', 'success');

      // Add the processClaim transaction to the history
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "", // Server will extract the real messageId if needed
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'processClaim',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString(),
          execNonce: execNonce
        });
        showToast('Transaction recorded in history!', 'success');
      }
    },
    onError: (err) => {
      showToast(`Error claiming rewards: ${err.message}`, 'error');
      console.error('Error:', err);
    }
  });

  // Fetch the current distribution root index
  const fetchCurrentDistRootIndex = async () => {
    if (!l1Wallet.publicClient) {
      setError('Ethereum Sepolia client not available');
      return;
    }

    try {
      setLoading(true);
      const rootsLength = await l1Wallet.publicClient.readContract({
        address: REWARDS_COORDINATOR_ADDRESS,
        abi: RewardsCoordinatorABI,
        functionName: 'getDistributionRootsLength'
      });

      // Convert to number and subtract 1 to get the latest index
      const latestIndex = Number(rootsLength) - 1;
      setCurrentDistRootIndex(latestIndex);
      setError(null);
    } catch (err) {
      console.error('Error fetching distribution roots length:', err);
      setError('Failed to fetch distribution roots. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  // Simulate the claim
  const simulateClaim = async () => {
    if (!l1Wallet.publicClient || !eigenAgentInfo?.eigenAgentAddress || currentDistRootIndex === null) {
      setError('Required data not available');
      return;
    }

    // Make sure we have a connected wallet address
    if (!l1Wallet.account) {
      setError('No wallet connected. Please connect your wallet first.');
      return;
    }

    try {
      setLoading(true);

      // Get proof data from service (in production, would be from API)
      const proofData = await getRewardsProofData(
        eigenAgentInfo.eigenAgentAddress,
        currentDistRootIndex
      );

      // Store the reward amount for display
      setRewardAmount(proofData.amount);
      setRewardToken(proofData.token);

      // Create the claim object
      const claim: RewardsMerkleClaim = createRewardClaim(
        currentDistRootIndex,
        eigenAgentInfo.eigenAgentAddress,
        proofData
      );

      // Simulate the claim
      const success = await simulateRewardClaim(
        l1Wallet.publicClient,
        l1Wallet.account,
        eigenAgentInfo.eigenAgentAddress,
        REWARDS_COORDINATOR_ADDRESS,
        claim,
        eigenAgentInfo.eigenAgentAddress
      );

      setSimulationResult(success);

      if (success) {
        showToast('Simulation successful! You can now claim your rewards.', 'success');
      } else {
        showToast('Simulation failed. You may not be eligible for rewards or there might be an issue with your claim.', 'error');
      }
    } catch (err) {
      console.error('Error simulating claim:', err);
      setError('Failed to simulate claim. Please try again.');
      setSimulationResult(false);
    } finally {
      setLoading(false);
    }
  };

  // Claim rewards
  const claimRewards = async () => {
    if (!eigenAgentInfo?.eigenAgentAddress || currentDistRootIndex === null) {
      setError('Required data not available');
      return;
    }

    try {
      // Get proof data from service
      const proofData = await getRewardsProofData(
        eigenAgentInfo.eigenAgentAddress,
        currentDistRootIndex
      );

      // Create the claim object
      const claim: RewardsMerkleClaim = createRewardClaim(
        currentDistRootIndex,
        eigenAgentInfo.eigenAgentAddress,
        proofData
      );

      // Encode the message for processing the claim
      const message = encodeProcessClaimMsg(claim, eigenAgentInfo.eigenAgentAddress);

      // Execute the message through the EigenAgent
      await executeWithMessage(message);

    } catch (err) {
      console.error('Error claiming rewards:', err);
      setError('Failed to claim rewards. Please try again.');
    }
  };

  // Fetch the current root index on mount
  useEffect(() => {
    if (l1Wallet.publicClient) {
      fetchCurrentDistRootIndex();
    }
  }, [l1Wallet.publicClient]);

  // Reset simulation results when eigenAgentInfo changes
  useEffect(() => {
    setSimulationResult(null);
  }, [eigenAgentInfo]);

  return (
    <div className="transaction-form">
      <h2>Claim Rewards</h2>

      {!isConnected ? (
        <p>Please connect your wallet to claim rewards</p>
      ) : isLoadingEigenAgent ? (
        <p>Loading your EigenAgent...</p>
      ) : !eigenAgentInfo?.eigenAgentAddress ? (
        <div className="no-agent-warning">
          <p>You need an EigenAgent to claim rewards. Please set up your EigenAgent first.</p>
        </div>
      ) : (
        <>
          <div className="form-group">
            <label>Eigenlayer Distribution Root Index: {currentDistRootIndex}</label>
          </div>

          {rewardAmount > 0n && (
            <div className="form-group">
              <label>MAGIC Reward Amount</label>
              <p className="monospace-text">{formatEther(rewardAmount)} MAGIC</p>
            </div>
          )}

          {simulationResult !== null && (
            <div className={`${simulationResult ? 'approval-status' : 'error-message'}`}>
              <h3>{simulationResult ? 'Simulation Successful' : 'Simulation Failed'}</h3>
              <p>
                {simulationResult
                  ? 'You can now proceed to claim your rewards.'
                  : 'You may not be eligible for rewards or there might be an issue with your claim.'}
              </p>
            </div>
          )}

          {error && (
            <div className="error-message">
              <p>{error}</p>
            </div>
          )}

          {operationError && (
            <div className="error-message">
              <p>{operationError}</p>
            </div>
          )}

          {operationInfo && (
            <div className="approval-status">
              <p>{operationInfo}</p>
            </div>
          )}

          <div className="rewards-button-container">
            <button
              className="eigenagent-check-button"
              onClick={simulateClaim}
              disabled={loading || isLoadingEigenAgent || currentDistRootIndex === null || !eigenAgentInfo?.eigenAgentAddress}
            >
              Simulate Claim
            </button>

            <button
              className="create-transaction-button"
              onClick={claimRewards}
              disabled={
                isExecuting ||
                loading ||
                isLoadingEigenAgent ||
                currentDistRootIndex === null ||
                !eigenAgentInfo?.eigenAgentAddress
                // Uncomment to require successful simulation before claiming
                // || (simulationResult !== null && !simulationResult)
              }
            >
              {isExecuting ? 'Processing...' : 'Claim Rewards'}
            </button>
          </div>
        </>
      )}
    </div>
  );
};

export default RewardsComponent;