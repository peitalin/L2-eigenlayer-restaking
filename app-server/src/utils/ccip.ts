import { CCIPMessageData } from '../types';
import { getStatusFromState } from './transaction';

// Function to fetch CCIP message data from an external API
export async function fetchCCIPMessageData(messageId: string): Promise<CCIPMessageData | null> {
  try {
    const response = await fetch(`https://ccip.chain.link/api/h/atlas/message/${messageId}`);
    if (!response.ok) {
      throw new Error(`Failed to fetch CCIP message data. Status: ${response.status}`);
    }

    const data = await response.json();

    // Map the API response to our simplified CCIPMessageData interface
    return {
      messageId: data.messageId,
      state: data.state,
      status: getStatusFromState(data.state, data), // Convert numeric state to string status
      sourceChainId: data.sourceChainId,
      destChainId: data.destChainId,
      receiptTransactionHash: data.receiptTransactionHash || null,
      destTxHash: data.receiptTransactionHash || null, // Use receiptTransactionHash as destTxHash
      data: data.data,
      sender: data.sender,
      receiver: data.receiver,
      execNonce: data.execNonce
    };
  } catch (error) {
    console.error(`Error fetching CCIP message data for messageId ${messageId}:`, error);
    return null;
  }
}

