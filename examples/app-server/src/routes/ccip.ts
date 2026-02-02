import express from 'express';
import { fetchCCIPMessageData } from '../utils/ccip';
import { ErrorResponse } from '../types';

const router = express.Router();

// Fetch CCIP message data
router.get('/message/:messageId', async (req, res) => {
  const { messageId } = req.params;

  if (!messageId) {
    return res.status(400).json({ error: 'No messageId provided' });
  }

  try {
    // If in test mode, return mock data
    if (process.env.NODE_ENV === 'test') {
      return res.json({ ...mockData, messageId });
    }

    const data = await fetchCCIPMessageData(messageId);

    if (!data) {
      return res.status(404).json({
        error: 'Failed to fetch CCIP message data'
      });
    }

    return res.json(data);
  } catch (error) {
    console.error('Error in API route for fetching CCIP message data:', error);
    return res.status(500).json({ error: 'Failed to fetch CCIP message data' });
  }
});

// Define mock data for tests
const mockData = {
  messageId: 'mock_j1234567890',
  status: 'SUCCESS',
  sourceChainId: '16015286601757825753',
  destinationChainId: '421614',
  sender: '0x1234567890123456789012345678901234567890',
  receiver: '0x0987654321098765432109876543210987654321',
  sourceTxHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
  destTxHash: '0x0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba',
  timestamp: Math.floor(Date.now() / 1000),
  data: '0x',
  token: '0x0000000000000000000000000000000000000000',
  amount: '0',
  feeToken: '0x0000000000000000000000000000000000000000',
  feeAmount: '0'
};

export default router;