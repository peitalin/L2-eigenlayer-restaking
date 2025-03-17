#!/bin/bash

# Check for imports from ERC20.ts
echo "Checking for imports from ./ERC20.ts"
grep -r "import.*from.*ERC20" --include="*.ts" --include="*.tsx" src/

# Check for exports from ERC20.ts
echo "Checking for exports from ERC20.ts"
grep -r "export.*from.*ERC20" --include="*.ts" --include="*.tsx" src/

# Check for usages of ERC20_ABI
echo "Checking for usages of ERC20_ABI"
grep -r "ERC20_ABI" --include="*.ts" --include="*.tsx" src/