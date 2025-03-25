# L2-eigenlayer-restaking Transaction Server

This server provides the following functionality:
- Stores transactions in a SQLite database for querying
- Tracks cross-chain transaction status using CCIP message IDs
- Provides endpoints for clients to add and query transactions
- Automatically updates transaction status in the background

## Codebase Structure

```
app-server/
├── src/                      # Source code
│   ├── data/                 # Sqlite3 database data
│   ├── db/                   # database logic
│   ├── routes/               # API routes
│   │   ├── index.ts          # Main router
│   │   └── transactions.ts   # Transaction routes
│   ├── signers/              # Signature services
│   ├── types/                # TypeScript type definitions
│   ├── utils/                # Utility functions
│   │   ├── logger.ts         # Logging utilities
│   │   ├── constants.ts      # Constants and event signatures
│   │   └── transaction.ts    # Transaction utilities
│   └── server.ts             # Main server entry point
├── data/                     # SQLite database storage
├── logs/                     # Application logs
└── db.js                     # Database interface
```

## Running the Server

### Development Mode (HTTP)

```bash
# Runs in HTTP mode (without SSL) for local development
npm run server:watch

```

### Production Mode (HTTPS)

You will need to generate SSL certs and then use `pm2`.
```bash
sh generate_ssl_certs.sh
```

Then run:
```bash
# Runs in HTTPS mode with SSL for production
npm install pm2 -g
pm2 start ecosystem.config.cjs
```

Stop the server with:
```bash
pm2 list
pm2 stop app-server
pm2 delete app-server
```


## Environment Variables

The following environment variables can be set in a `.env` file:

- `SERVER_PORT`: Port to run the server on (default: 3001)
- `USE_SSL`: Set to 'true' to enable HTTPS (default: 'false')
- `LOG_LEVEL`: Sets logging level ('error', 'warn', 'info', 'http', 'debug')
- `DELEGATION_MANAGER_ADDRESS`: Address of the delegation manager contract
- `SEPOLIA_RPC_URL`: RPC URL for Ethereum Sepolia
- `BASE_SEPOLIA_RPC_URL`: RPC URL for Base Sepolia
- `OPERATOR_KEY1` through `OPERATOR_KEY10`: Private keys for operators

## API Endpoints

### Transactions

- `GET /api/transactions` - Get all transactions
- `GET /api/transactions/user/:address` - Get transactions for a specific user
- `GET /api/transactions/hash/:txHash` - Get transaction by hash
- `GET /api/transactions/messageId/:messageId` - Get transaction by CCIP message ID
- `POST /api/transactions/add` - Add a new transaction

### CCIP Messages

- `GET /api/ccip/message/:messageId` - Get CCIP message data

### EigenAgents

- `GET /api/execnonce/:agentAddress` - Get the latest execution nonce for an EigenAgent

## Implementation Notes

### receiptTransactionHash Handling

The codebase has been updated to ensure that `receiptTransactionHash` (on the destination chain) is never the same as the original transaction hash from the source chain. If they are the same, the `receiptTransactionHash` will be set to `undefined` to avoid confusion.

### Logging

The server uses Winston for structured logging with different log levels:
- `error`: Critical errors that require immediate attention
- `warn`: Warnings that don't stop the application but should be investigated
- `info`: Important runtime events (server start/stop, initialization)
- `http`: HTTP request logs
- `debug`: Detailed information for debugging

Logs are output to both the console and log files in the `logs/` directory.