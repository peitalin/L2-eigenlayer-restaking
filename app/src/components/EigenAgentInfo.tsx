import React from 'react';
import { useClientsContext } from '../contexts/ClientsContext';
import UserDeposits from './UserDeposits';

const EigenAgentInfo: React.FC = () => {
  const {
    l1Wallet,
    isConnected,
    eigenAgentInfo,
    isLoadingEigenAgent,
    fetchEigenAgentInfo
  } = useClientsContext();

  return (
    <div className="right-column-content">
      <div className="eigenagent-info">
        <h3>EigenAgent Information (Ethereum Sepolia)</h3>
        {!isConnected ? (
          <p>Connect your wallet to view EigenAgent information</p>
        ) : !l1Wallet.account ? (
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
              disabled={isLoadingEigenAgent || !isConnected}
            >
              Refresh EigenAgent Info
            </button>
          </div>
        ) : (
          <p>Failed to load EigenAgent information</p>
        )}
      </div>

      <UserDeposits />

      {!isConnected && (
        <div className="connection-message">
          <h3>Wallet Not Connected</h3>
          <p>
            Please connect your wallet using the "Connect" button in the navigation bar
            to interact with EigenLayer.
          </p>
        </div>
      )}

      {isConnected && !eigenAgentInfo?.eigenAgentAddress && (
        <div className="no-agent-warning">
          <h3>No EigenAgent Found</h3>
          <p>
            You need to create an EigenAgent on Ethereum Sepolia before you can interact with strategies.
          </p>
        </div>
      )}
    </div>
  );
};

export default EigenAgentInfo;