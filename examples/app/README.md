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


## Testing
Run tests with:

```bash
pnpm test
```


## Current Networks
- Ethereum Sepolia (Chain ID: 11155111)
- Base Sepolia (Chain ID: 84532)


## Project Structure

```
src/
  abis/             # Smart contract ABIs and types
  components/       # UI components
  addresses/        # network addresses, constants.
  contexts/         # React context providers / state
  hooks/            # React hooks
  pages/            # Pages for routes
  styles/           # CSS styling
  tests/            # Contract signing tests
  types/            # type definitions
  utils/            # utility functions
```


### Configuration

Configuration is in the `src/config` directory:

- `networks.ts`: Network definitions (ChainIDs, RPC URLs, etc.)
- `contracts.ts`: Smart contract addresses by network
- `index.ts`: App-wide constants like gas limits and timeouts

### State Management

The app uses React Context for state management:

- `ClientsContext`: Manages wallet connections and client instances
- `TransactionHistoryContext`: Tracks transaction history (syncs with `app-server/server.ts`)

### Eigenlayer Operations

The EigenAgent calls are split into the following modules:
1. `useEigenLayerOperation`: The main hook that orchestrates signing EigenAgent messages, approvals, estimating fees, and dispatching CCIP messages
2. `tokenApproval`: Handles token approvals
3. `dispatchTransaction`: Handles CCIP cross-chain transactions
4. `utils`: Common utilities for EigenLayer operations
