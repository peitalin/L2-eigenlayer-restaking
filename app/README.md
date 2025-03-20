# EigenLayer Restaking Frontend

Frontend for the EigenLayer L2 Restaking application that allows users to interact with EigenLayer entirely from L2

## Getting Started

### Installation

1. Install dependencies:
```bash
cd app
pnpm install
```

2. Setup environment variables (if running tests):
```bash
cp .env.example .env
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

Make sure the app-server is running on http://localhost:3001 for the frontend to communicate with CCIP explorer API.


## Current Networks
- Ethereum Sepolia (Chain ID: 11155111)
- Base Sepolia (Chain ID: 84532)
