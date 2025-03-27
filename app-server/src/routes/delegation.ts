import express from 'express';
import { signDelegationApproval } from '../signers/signDelegationApproval';
import { ErrorResponse } from '../types';
import { operatorAddressToKey } from '../utils/operators';

const router = express.Router();

// Helper function to convert BigInt values to strings
function serializeBigInt(obj: any): any {
  if (obj === null || obj === undefined) {
    return obj;
  }

  if (typeof obj === 'bigint') {
    return obj.toString();
  }

  if (Array.isArray(obj)) {
    return obj.map(serializeBigInt);
  }

  if (typeof obj === 'object') {
    const result: Record<string, any> = {};
    for (const [key, value] of Object.entries(obj)) {
      result[key] = serializeBigInt(value);
    }
    return result;
  }

  return obj;
}

router.post('/sign', async (req, res) => {
  try {
    const { staker, operator } = req.body;

    // Validate input parameters
    if (!staker || !operator) {
      return res.status(400).json({
        error: 'Missing required parameters'
      });
    }

    // Validate addresses
    if (!staker.startsWith('0x') || !operator.startsWith('0x')) {
      return res.status(400).json({
        error: 'Invalid address format'
      });
    }

    // Get operator key from map. Only for testing purposes.
    // In production we query Eigenlayer's API to sign the message.
    const operatorKey = operatorAddressToKey.get(operator.toLowerCase());
    if (!operatorKey) {
      return res.status(401).json({
        error: 'Unauthorized operator address'
      });
    }

    // Set expiry to 7 days from now
    const expiry = BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60);

    const result = await signDelegationApproval(staker, operator, operatorKey as `0x${string}`, expiry);

    // Serialize BigInt values before sending the response
    res.json(serializeBigInt(result));
  } catch (error) {
    const errorResponse = error as ErrorResponse;
    console.error('Error in delegation signing endpoint:', error);
    // Return a 401 status if the operator is not authorized
    if (errorResponse.message === 'Unauthorized operator address') {
      return res.status(401).json({
        error: 'Unauthorized operator address'
      });
    }

    res.status(500).json({
      error: 'Failed to sign delegation approval',
      details: errorResponse.message
    });
  }
});

export default router;
