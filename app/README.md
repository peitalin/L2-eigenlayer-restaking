# EigenLayer Restaking Frontend

Frontend for the EigenLayer L2 Restaking application that allows users to interact with EigenLayer entirely from L2

## Getting Started

### Prerequisites

- Node.js (v18 or higher)
- npm or pnpm
- MetaMask or another Ethereum wallet

### Installation

1. Install dependencies:
```bash
cd app
pnpm install
```

2. Setup environment variables (for tests only):
```bash
cp .env.example .env.local
```

### Starting the Frontend

#### Development Mode
```bash
npm run dev
# or
pnpm dev
```

The frontend will be available at http://localhost:5173

#### Production Build
```bash
npm run build
npm run preview
# or
pnpm build
pnpm preview
```

## Connecting to the Backend

Make sure the app-server is running on http://localhost:3001 for the frontend to communicate with the backend API.


At the moment I will need to set you up with:
- and EigenAgent mint
- Some testnet mock CCIP MAGIC

## Supported Networks

- Ethereum Sepolia (Chain ID: 11155111)
- Base Sepolia (Chain ID: 84532)

## Features

- Connect wallet and view balances
- Deposit assets into EigenLayer strategies
- Queue and complete withdrawals
- Track transaction history
- Process rewards claims