// Import ABIs from JSON files
import AgentFactoryJSON from './AgentFactory.json';
import EigenAgentJSON from './EigenAgent6551.json';
import SenderCCIPJSON from './SenderCCIP.json';
import StrategyManagerJSON from './StrategyManager.json';

// Export ABIs directly
export const agentFactoryAbi = AgentFactoryJSON.abi;
export const eigenAgentAbi = EigenAgentJSON.abi;
export const senderCCIPAbi = SenderCCIPJSON.abi;
export const strategyManagerAbi = StrategyManagerJSON.abi;

// Export chainlink ABIs
export * from './Router';