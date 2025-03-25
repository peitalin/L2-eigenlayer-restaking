import { Router } from 'express';
import * as db from '../db';

const router = Router();

// GET all transactions
router.get('/', (req, res) => {
  try {
    const transactions = db.getAllTransactions();
    res.json(transactions);
  } catch (error) {
    console.error('Error reading transaction history:', error);
    res.status(500).json({ error: 'Failed to read transaction history' });
  }
});

// Add other transaction routes here with the base path removed
// (i.e., '/api/transactions' becomes '/')

export default router;
