# EigenLayer Restaking App

A decentralized application for interacting with EigenLayer's restaking protocol, featuring cross-chain transaction support via Chainlink CCIP.

## Features

- Deposit assets into EigenLayer strategies
- Queue and complete withdrawals
- Track cross-chain transactions with CCIP message status
- Persistent transaction history

## Prerequisites

- Node.js (v18 or higher)
- npm or pnpm

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd L2-eigenlayer-restaking/app
```

2. Install dependencies:
```bash
npm install
# or with pnpm
pnpm install
```

3. Set up environment variables:
```bash
cp .env.example .env
```

Edit the `.env` file with your configuration:
```
SERVER_PORT=3001
VITE_API_URL=http://localhost:3001/api
```

## Running the Application

### Development Mode

To run both the frontend and backend server in development mode:

```bash
npm run dev:all
```

This will start:
- Frontend React app on http://localhost:5173
- Backend API server on http://localhost:3001

### Run Frontend Only

```bash
npm run dev
```

### Run Backend Server Only

```bash
npm run server
# or with file watching for development
npm run server:watch
```

## API Endpoints

The backend server provides the following endpoints:

### CCIP Data

- `GET /api/ccip/message/:messageId` - Fetch CCIP message data for a specific messageId

### Transaction History

- `GET /api/transactions` - Get all saved transactions
- `POST /api/transactions` - Save a list of transactions
- `POST /api/transactions/add` - Add a new transaction
- `PUT /api/transactions/:txHash` - Update a transaction by its txHash
- `PUT /api/transactions/messageId/:messageId` - Update a transaction by its messageId
- `DELETE /api/transactions` - Clear all transaction history

## Project Structure

- `/src` - Frontend React application
  - `/components` - UI components
  - `/contexts` - React context providers
  - `/hooks` - Custom React hooks
  - `/utils` - Utility functions
  - `/styles` - CSS styles
- `/server.ts` - Backend Express server
- `/data` - Data storage for the server (created at runtime)

## Building for Production

```bash
# Build the frontend
npm run build

# Run the production server
NODE_ENV=production npm run server
```

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.