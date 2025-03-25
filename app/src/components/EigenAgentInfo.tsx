import React from 'react';
import { useClientsContext } from '../contexts/ClientsContext';
import { EIGEN_AGENT_OWNER_721_ADDRESS } from '../addresses';

const EigenAgentInfo: React.FC = () => {
  const {
    isConnected,
    eigenAgentInfo,
    isLoadingEigenAgent,
    fetchEigenAgentInfo
  } = useClientsContext();

  return (
    <div className="treasure-info-section">
      <div style={{ position: "relative" }}>
        <h2>
          Eigenlayer Staking from L2 <br/>
          with EigenAgent NFTs
        </h2>
        <img
          src="/assets/logos/treasure/eigenlayer-logo.webp"
          alt="EigenLayer Logo"
          style={{
            width: '32px',
            height: '32px',
            borderRadius: '8px',
            padding: '4px',
            backgroundColor: 'white',
            objectFit: 'contain',
            position: 'absolute',
            top: '8px',
            right: '0px'
          }}
        />
      </div>

      {!isConnected ? (
        <p>Connect your wallet to view EigenAgent information</p>
      ) : isLoadingEigenAgent ? (
        <div style={{ display: 'flex', justifyContent: 'center', padding: '20px 0' }}>
          <div className="loading-spinner"></div>
        </div>
      ) : !eigenAgentInfo?.eigenAgentAddress ? (
        <div style={{ padding: '12px', backgroundColor: 'rgba(247, 179, 0, 0.1)', borderRadius: '8px', fontSize: '0.9rem' }}>
          <p>You don't have an EigenAgent set up yet. Please create one to use EigenLayer operations.</p>
        </div>
      ) : (
        <>
          <div className="treasure-info-item">
            <div className="treasure-info-label">EigenAgent NFT:</div>
            <div className="treasure-info-value">
              {eigenAgentInfo?.eigenAgentAddress && (
                <>
                  {EIGEN_AGENT_OWNER_721_ADDRESS.substring(0, 7)}...{EIGEN_AGENT_OWNER_721_ADDRESS.substring(eigenAgentInfo.eigenAgentAddress.length - 4)}
                  <a
                    href={`https://sepolia.etherscan.io/address/${EIGEN_AGENT_OWNER_721_ADDRESS}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="treasure-link-icon"
                  >
                    ↗
                  </a>
                </>
              )}
            </div>
          </div>

          <div className="treasure-info-item">
            <div className="treasure-info-label">EigenAgent Account:</div>
            <div className="treasure-info-value">
              {eigenAgentInfo?.eigenAgentAddress && (
                <>
                  {eigenAgentInfo.eigenAgentAddress.substring(0, 7)}...{eigenAgentInfo.eigenAgentAddress.substring(eigenAgentInfo.eigenAgentAddress.length - 4)}
                  <a
                    href={`https://sepolia.etherscan.io/address/${eigenAgentInfo.eigenAgentAddress}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="treasure-link-icon"
                  >
                    ↗
                  </a>
                </>
              )}
            </div>
          </div>

          <div className="treasure-info-item">
            <div className="treasure-info-label">EigenAgent Nonce:</div>
            <div className="treasure-info-value">
              {eigenAgentInfo?.eigenAgentAddress && (
                <>
                  {Number(eigenAgentInfo.execNonce)}
                  <div style={{ opacity: '0' }}>
                    ↗
                  </div>
                </>
              )}
            </div>
          </div>


          <div className="treasure-info-item">
            <div style={{ fontSize: '0.9rem', lineHeight: '1.5' }}>
              <p>
                Stake Magic into Eigenlayer on L1 directly from L2 Treasure Chain using
                ERC-6551 EigenAgent accounts. Your Magic deposit is routed to
                your EigenAgent on L1, who deposits it for you into Eigenlayer. It also handles
                delegation, withdrawals and rewards claiming on your behalf.
              </p>
              <p>
                Your wallet owns the EigenAgent NFT and it's associated ERC-6551
                account, so don't lose the NFT!
              </p>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

export default EigenAgentInfo;