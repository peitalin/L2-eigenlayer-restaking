# EigenLayer Restaking Server

Server for tracking transaction history and CCIP message history for the EigenLayer L2 Restaking application.

## Getting Started

### Installation

1. Install dependencies:
```bash
cd app-server
pnpm install
```

### Starting the Server

The server will run on http://localhost:3001
```bash
npm run start:watch
```
The server will migrate some `transactions.json` demo data first.

Then it will receive CCIP transactions/messages from the frontend and poll them to see when the finish on L1, and check whether there are follow-up CCIP messages that it needs to track for the frontend (e.g claiming rewards, withdrawals)


## API Endpoints

- `GET /api/transactions` - Get all transactions
- `POST /api/transactions/add` - Add a new transaction
- `PUT /api/transactions/:txHash` - Update transaction by hash
- `GET /api/transactions/pending` - Get pending transactions