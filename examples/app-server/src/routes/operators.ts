import express from 'express';
import { OPERATORS_DATA, operatorsByAddress } from '../utils/operators';

const router = express.Router();

// Get all operators
router.get('/', (req, res) => {
  try {
    // Return only active operators by default
    const showInactive = req.query.showInactive === 'true';
    const operators = showInactive
      ? OPERATORS_DATA
      : OPERATORS_DATA.filter(op => op.isActive);

    res.json(operators);
  } catch (error) {
    console.error('Error fetching operators:', error);
    res.status(500).json({ error: 'Failed to fetch operators' });
  }
});

// Get operator by address
router.get('/:address', (req, res) => {
  try {
    const { address } = req.params;
    const operator = operatorsByAddress.get(address.toLowerCase());

    if (!operator) {
      return res.status(404).json({ error: 'Operator not found' });
    }

    res.json(operator);
  } catch (error) {
    console.error('Error fetching operator:', error);
    res.status(500).json({ error: 'Failed to fetch operator' });
  }
});

export default router;
