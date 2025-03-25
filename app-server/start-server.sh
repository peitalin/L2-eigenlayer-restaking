#!/bin/bash

# Set environment variables
export USE_SSL=false
export NODE_ENV=production
export PORT=3001

# Start the server using npx tsx
npx tsx src/server.ts --port 3001