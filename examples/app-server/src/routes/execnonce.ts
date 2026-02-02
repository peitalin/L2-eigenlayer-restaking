import express from 'express';
import * as db from '../db';

const router = express.Router();

// GET latest execNonce for an EigenAgent
router.get('/:agentAddress', (req, res) => {
  try {
    const { agentAddress } = req.params;

    if (!agentAddress || !agentAddress.startsWith('0x')) {
      return res.status(400).json({ error: 'Invalid EigenAgent address' });
    }

    const latestNonce = db.getLatestExecNonceForAgent(agentAddress.toLowerCase());

    // If no nonce is found, return 0 as the starting nonce
    const nextNonce = latestNonce !== null ? latestNonce + 1 : 0;

    res.json({
      agentAddress: agentAddress.toLowerCase(),
      latestNonce: latestNonce,
      nextNonce: nextNonce
    });
  } catch (error) {
    console.error('Error fetching execNonce:', error);
    res.status(500).json({ error: 'Failed to fetch execNonce' });
  }
});

export default router;