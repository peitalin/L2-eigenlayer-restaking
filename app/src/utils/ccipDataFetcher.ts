// Define server base URL
const SERVER_BASE_URL = 'http://localhost:3001';

// Define the structure of the CCIP message data from the API
export interface CCIPMessageData {
  messageId: string;
  state: number;
  votes: any;
  sourceNetworkName: string;
  destNetworkName: string;
  commitBlockTimestamp: string;
  root: string;
  sendFinalized: string;
  commitStore: string;
  origin: string;
  sequenceNumber: number;
  sender: string;
  receiver: string;
  sourceChainId: string;
  destChainId: string;
  routerAddress: string;
  onrampAddress: string;
  offrampAddress: string;
  destRouterAddress: string;
  sendTransactionHash: string;
  sendTimestamp: string;
  sendBlock: number;
  sendLogIndex: number;
  min: string;
  max: string;
  commitTransactionHash: string;
  commitBlockNumber: number;
  commitLogIndex: number;
  arm: string;
  blessTransactionHash: string | null;
  blessBlockNumber: string | null;
  blessBlockTimestamp: string | null;
  blessLogIndex: string | null;
  receiptTransactionHash: string | null;
  receiptTimestamp: string | null;
  receiptBlock: number | null;
  receiptLogIndex: number | null;
  receiptFinalized: string | null;
  data: string;
  strict: boolean;
  nonce: number;
  feeToken: string;
  gasLimit: string;
  feeTokenAmount: string;
  tokenAmounts: any[];
}

/**
 * Fetches CCIP message data from the server API
 * @param messageId The CCIP message ID to fetch data for
 * @returns A promise that resolves to the CCIP message data
 */
export async function fetchCCIPMessageData(messageId: string): Promise<CCIPMessageData | null> {
  if (!messageId || messageId === '') {
    console.log('No messageId provided to fetchCCIPMessageData');
    return null;
  }

  try {
    console.log(`Fetching CCIP data for messageId: ${messageId}`);

    // Use the app server API instead of calling CCIP API directly
    const response = await fetch(`${SERVER_BASE_URL}/api/ccip/message/${messageId}`);

    if (!response.ok) {
      console.error(`Error fetching CCIP data: ${response.status} ${response.statusText}`);
      return null;
    }

    const data = await response.json();
    console.log('CCIP data received:', data);
    return data as CCIPMessageData;
  } catch (error) {
    console.error('Error fetching CCIP message data:', error);
    return null;
  }
}

/**
 * Utility to convert CCIP message state to a human-readable status
 * @param state CCIP message state number
 * @returns Human-readable status
 */
export function getCCIPMessageStatusText(state: number): string {
  switch (state) {
    case 0:
      return 'Pending';
    case 1:
      return 'In Flight';
    case 2:
      return 'Confirmed';
    case 3:
      return 'Failed';
    default:
      return 'Unknown';
  }
}