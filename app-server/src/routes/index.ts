import express from 'express';

// Create the main router
export const router = express.Router();

// Add a health check endpoint for checking API status
router.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

// Export the router as both default and named export
export default router;