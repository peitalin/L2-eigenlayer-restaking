import request from 'supertest';
import { app } from '../server';

describe('API Routes', () => {
  describe('CCIP Routes', () => {
    it('should have GET /api/ccip/message/:messageId endpoint', async () => {
      const response = await request(app).get('/api/ccip/message/test-message-id');
      expect(response.status).not.toBe(404);
    });
  });

  describe('Transaction Routes', () => {
    it('should have GET /api/transactions/user/:address endpoint', async () => {
      const response = await request(app).get('/api/transactions/user/0x123');
      expect(response.status).not.toBe(404);
    });

    it('should have GET /api/transactions/hash/:txHash endpoint', async () => {
      const response = await request(app).get('/api/transactions/hash/0x123');
      expect(response.status).not.toBe(404);
    });

    it('should have GET /api/transactions/messageId/:messageId endpoint', async () => {
      const response = await request(app).get('/api/transactions/messageId/test-message');
      expect(response.status).not.toBe(404);
    });

    it('should have POST /api/transactions/add endpoint', async () => {
      const mockTransaction = {
        txHash: '0x123',
        messageId: 'test-message',
        txType: 'deposit',
        status: 'pending',
        from: '0x456',
        to: '0x789',
        user: '0x456'
      };
      const response = await request(app)
        .post('/api/transactions/add')
        .send(mockTransaction);
      expect(response.status).not.toBe(404);
    });

    it('should have PUT /api/transactions/:txHash endpoint', async () => {
      const response = await request(app)
        .put('/api/transactions/0x123')
        .send({ status: 'confirmed' });
      expect(response.status).not.toBe(404);
    });

    it('should have PUT /api/transactions/messageId/:messageId endpoint', async () => {
      const response = await request(app)
        .put('/api/transactions/messageId/test-message')
        .send({ status: 'confirmed' });
      expect(response.status).not.toBe(404);
    });
  });

  describe('ExecNonce Routes', () => {
    it('should have GET /api/execnonce/:agentAddress endpoint', async () => {
      const response = await request(app).get('/api/execnonce/0x123');
      expect(response.status).not.toBe(404);
    });
  });

  describe('Delegation Routes', () => {
    it('should have POST /api/delegation/sign endpoint', async () => {
      const mockDelegation = {
        staker: '0x123',
        operator: '0x456'
      };
      const response = await request(app)
        .post('/api/delegation/sign')
        .send(mockDelegation);
      expect(response.status).not.toBe(404);
    });
  });

  describe('Operator Routes', () => {
    it('should have GET /api/operators endpoint', async () => {
      const response = await request(app).get('/api/operators');
      expect(response.status).not.toBe(404);
    });

    it('should have GET /api/operators/:address endpoint', async () => {
      const response = await request(app).get('/api/operators/0x123');
      expect(response.status).not.toBe(404);
    });

    it('should support showInactive query parameter', async () => {
      const response = await request(app).get('/api/operators?showInactive=true');
      expect(response.status).not.toBe(404);
    });
  });

  // Test response format for each endpoint
  describe('Response Format Tests', () => {
    it('should return JSON for CCIP message data', async () => {
      const response = await request(app).get('/api/ccip/message/test-message-id');
      expect(response.headers['content-type']).toMatch(/json/);
    });

    it('should return JSON for transactions', async () => {
      const response = await request(app).get('/api/transactions/user/0x123');
      expect(response.headers['content-type']).toMatch(/json/);
    });

    it('should return JSON for execnonce', async () => {
      const response = await request(app).get('/api/execnonce/0x123');
      expect(response.headers['content-type']).toMatch(/json/);
    });

    it('should return JSON for operators', async () => {
      const response = await request(app).get('/api/operators');
      expect(response.headers['content-type']).toMatch(/json/);
    });
  });

  // Test error handling
  describe('Error Handling Tests', () => {
    it('should handle invalid transaction data', async () => {
      const response = await request(app)
        .post('/api/transactions/add')
        .send({});
      expect(response.status).toBe(400);
    });

    it('should handle invalid delegation data', async () => {
      const response = await request(app)
        .post('/api/delegation/sign')
        .send({});
      expect(response.status).toBe(400);
    });

    it('should handle non-existent operator', async () => {
      const response = await request(app)
        .get('/api/operators/0xnonexistent');
      expect(response.status).toBe(404);
    });
  });
});