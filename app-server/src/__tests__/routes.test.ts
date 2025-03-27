import { config } from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { describe, it, expect, vi, beforeAll } from 'vitest';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load test environment variables before importing app
config({ path: path.join(__dirname, 'test.env') });

// Set up mocks
vi.mock('../db', () => ({
  getTransactionsByUser: vi.fn().mockReturnValue([]),
  getTransactionByHash: vi.fn().mockReturnValue({}),
  getTransactionByMessageId: vi.fn().mockReturnValue({}),
  addTransaction: vi.fn().mockImplementation(tx => tx),
  updateTransaction: vi.fn().mockImplementation((txHash, updates) => ({ txHash, ...updates })),
  updateTransactionByMessageId: vi.fn().mockImplementation((messageId, updates) => ({ messageId, ...updates })),
  getLatestExecNonceForAgent: vi.fn().mockReturnValue(0),
  getPendingTransactions: vi.fn().mockReturnValue([]),
  addTransactions: vi.fn()
}));

vi.mock('../utils/operators', () => ({
  OPERATORS_DATA: [
    {
      address: "0x123",
      name: "Test Operator",
      logo: "test.png",
      isActive: true
    }
  ],
  operatorsByAddress: new Map([
    ["0x123", { address: "0x123", name: "Test Operator", logo: "test.png", isActive: true }]
  ]),
  operatorAddressToKey: new Map([
    ["0x456", "0x1234567890123456789012345678901234567890123456789012345678901234"]
  ])
}));

vi.mock('../signers/signDelegationApproval', () => ({
  signDelegationApproval: vi.fn().mockResolvedValue({
    signature: '0x1234',
    expiry: 123456789n // Changed to string to avoid BigInt serialization issues
  })
}));

vi.mock('../utils/ccip', () => ({
  fetchCCIPMessageData: vi.fn().mockResolvedValue({
    messageId: 'test-message-id',
    status: 'SUCCESS'
  })
}));

vi.mock('../utils/transaction', () => ({
  extractMessageIdFromTxHash: vi.fn().mockResolvedValue({
    messageId: 'test-message-id',
    agentOwner: '0x123'
  }),
  updateTransactionStatus: vi.fn().mockResolvedValue(true)
}));

vi.mock('../utils/clients', () => {
  const mockClient = {
    request: vi.fn().mockResolvedValue({})
  };

  return {
    publicClientL1: mockClient,
    publicClientL2: mockClient,
    determineClientFromTransaction: vi.fn().mockReturnValue(mockClient)
  };
});

// Make sure we don't start the server or initialize the database during tests
vi.mock('../server', async () => {
  const actual = await vi.importActual('../server.js');

  // Prevent the server from attempting to listen on a port
  if (actual.server) {
    actual.server.listen = vi.fn();
    actual.server.close = vi.fn();
  }

  return {
    ...actual,
    // Prevent server processes from starting
    startPendingTransactionChecker: vi.fn(),
    updatePendingTransactions: vi.fn()
  };
});

// Import after mocks are set up
import request from 'supertest';
import { app } from '../server.js';

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
        user: '0x456',
        sourceChainId: '84532', // Base Sepolia chain ID
        destinationChainId: '11155111' // Sepolia chain ID
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

  // Error tests can also be added here
});