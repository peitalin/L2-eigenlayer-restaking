import React from 'react';
import { useClientsContext } from '../contexts/ClientsContext';

const EigenAgentInfo: React.FC = () => {
  const {
    isConnected,
    eigenAgentInfo,
    isLoadingEigenAgent,
    fetchEigenAgentInfo
  } = useClientsContext();

  return (
    <div className="eigenagent-info">
      {!isConnected ? (
        <p>Connect your wallet to view EigenAgent information</p>
      ) : isLoadingEigenAgent ? (
        <p>Loading EigenAgent information...</p>
      ) : !eigenAgentInfo?.eigenAgentAddress ? (
        <div className="no-agent-warning">
          <p>You don't have an EigenAgent set up yet. Please create one to use EigenLayer operations.</p>
        </div>
      ) : (
        <>
          <div className="info-item">
            <strong>EigenAgent Address</strong>
            <div className="eigenagent-address">{eigenAgentInfo.eigenAgentAddress}</div>
          </div>

          <div className="info-item">
            <strong>Execution Nonce</strong>
            <div className="execution-nonce">{eigenAgentInfo.execNonce.toString()}</div>
          </div>

          <button
            className="eigenagent-check-button"
            onClick={fetchEigenAgentInfo}
          >
            Refresh
          </button>
        </>
      )}
    </div>
  );
};

export default EigenAgentInfo;