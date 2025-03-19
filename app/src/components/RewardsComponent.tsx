import React, { useState, useEffect } from 'react';
import { Address, Hex } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { encodeProcessClaimMsg } from '../utils/encoders';
import { REWARDS_COORDINATOR_ADDRESS } from '../addresses';
import { createClaim, REWARDS_AMOUNT, simulateRewardClaim } from '../utils/rewards';
import { RewardsMerkleClaim } from '../abis/generated/RewardsCoordinatorTypes';
import { RewardsCoordinatorABI } from '../abis';
import { useToast } from '../utils/toast';

const RewardsComponent: React.FC = () => {
  const {
    l1Wallet,
    isConnected,
    eigenAgentInfo,
    isLoadingEigenAgent,
    fetchEigenAgentInfo
  } = useClientsContext();
  const { showToast } = useToast();

  const [currentRootIndex, setCurrentRootIndex] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [simulationResult, setSimulationResult] = useState<boolean | null>(null);
  const [tokenAddress, setTokenAddress] = useState<Address>('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'); // Default to native token

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
    onSuccess: (txHash) => {
      showToast('Rewards claim transaction submitted!', 'success');
      console.log('Transaction hash:', txHash);
    },
    onError: (err) => {
      showToast(`Error claiming rewards: ${err.message}`, 'error');
      console.error('Error:', err);
    }
  });

  // Fetch the current distribution root index
  const fetchCurrentRootIndex = async () => {
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
      setCurrentRootIndex(latestIndex);
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
    if (!l1Wallet.publicClient || !eigenAgentInfo?.eigenAgentAddress || currentRootIndex === null) {
      setError('Required data not available');
      return;
    }

    try {
      setLoading(true);

      // Create the claim object
      const claim = createClaim(
        currentRootIndex,
        eigenAgentInfo.eigenAgentAddress as Address,
        REWARDS_AMOUNT,
        '0x', // Empty proof for single claim
        0,    // Earner index
        tokenAddress
      );

      // Simulate the claim
      const success = await simulateRewardClaim(
        l1Wallet.publicClient,
        eigenAgentInfo.eigenAgentAddress as Address,
        REWARDS_COORDINATOR_ADDRESS,
        claim,
        eigenAgentInfo.eigenAgentAddress as Address
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
    if (!eigenAgentInfo?.eigenAgentAddress || currentRootIndex === null) {
      setError('Required data not available');
      return;
    }

    try {
      // Create the claim object
      const claim: RewardsMerkleClaim = createClaim(
        currentRootIndex,
        eigenAgentInfo.eigenAgentAddress as Address,
        REWARDS_AMOUNT,
        '0x', // Empty proof for single claim
        0     // Earner index
      );

      // Encode the message for processing the claim
      const message = encodeProcessClaimMsg(claim, eigenAgentInfo.eigenAgentAddress as Address);

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
      fetchCurrentRootIndex();
    }
  }, [l1Wallet.publicClient]);

  // Handle changes to eigenAgentInfo
  useEffect(() => {
    // Reset any simulation results when eigenAgentInfo changes
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
            <label>Current Distribution Root Index</label>
            {loading ? (
              <p>Loading...</p>
            ) : currentRootIndex !== null ? (
              <p className="monospace-text">{currentRootIndex}</p>
            ) : (
              <p>Not available</p>
            )}
          </div>

          <div className="form-group">
            <label>Your EigenAgent</label>
            <p className="monospace-text">{eigenAgentInfo.eigenAgentAddress}</p>
          </div>

          <div className="form-group">
            <label>Execution Nonce</label>
            <p className="monospace-text">{eigenAgentInfo.execNonce.toString()}</p>
          </div>

          <div className="form-group">
            <label>Reward Amount</label>
            <p className="monospace-text">{REWARDS_AMOUNT.toString()} wei</p>
          </div>

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

          <div style={{ display: 'flex', gap: '10px', marginTop: '20px' }}>
            <button
              className="eigenagent-check-button"
              onClick={simulateClaim}
              disabled={loading || isLoadingEigenAgent || currentRootIndex === null || !eigenAgentInfo?.eigenAgentAddress}
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
                currentRootIndex === null ||
                !eigenAgentInfo?.eigenAgentAddress ||
                (simulationResult !== null && !simulationResult)
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