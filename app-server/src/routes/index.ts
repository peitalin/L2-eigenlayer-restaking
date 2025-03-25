import express from 'express';

const router = express.Router();

// Simple health check endpoint
router.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0' });
});

export { router };