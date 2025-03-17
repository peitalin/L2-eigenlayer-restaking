#!/bin/bash

# Create a list of CSS classes manually
cat > css_classes.txt << 'EOF'
app-container
content-container
navbar
navbar-title
navbar-actions
navbar-wallet-info
switch-chain-button
connect-button
connection-error
wallet-info
current-chain
current-account
wallet-navbar
navbar-left
navbar-links
navbar-link
navbar-info
navbar-section
section-label
section-value
disconnect-button
wallet-connect-page
connect-container
deposit-page
page-layout
left-column
right-column
transaction-form
form-group
input-note
create-transaction-button
eigenagent-info
eigenagent-address
execution-nonce
eigenagent-check-button
no-agent-warning
error-message
approval-status
account-balances
balance-item
balance-label
balance-value
connected-address
chain-selector
chain-controls
chain-id
wallet-connect
connection-info
wallet-address
wallet-address-short
refresh-button
refresh-balance-button
refresh-fee-button
fee-display
connection-message
navigation-panel
navigation-list
navigation-item
navigation-link
user-deposits
user-deposits-header
refresh-deposits-button
no-deposits-message
deposits-loading
deposits-error
deposits-table
deposit-item
deposit-strategy
strategy-name
strategy-address
deposit-shares
withdrawal-info
info-item
EOF

# Check usage of each class in the codebase
echo "Checking for unused CSS classes..."
UNUSED_CLASSES=""

while IFS= read -r class_name; do
  # Skip empty lines
  if [ -z "$class_name" ]; then
    continue
  fi

  # Look for this class name in className attributes in React components
  result=$(grep -r "className=.*['\"].*${class_name}.*['\"]" --include="*.tsx" --include="*.jsx" app/src/)

  # Also check for classes in active state (navigation-link.active etc.)
  active_result=$(grep -r "isActive.*${class_name}" --include="*.tsx" --include="*.jsx" app/src/)

  if [ -z "$result" ] && [ -z "$active_result" ]; then
    UNUSED_CLASSES+="$class_name\n"
  fi
done < css_classes.txt

# Output the unused classes
echo -e "The following CSS classes appear to be unused:\n$UNUSED_CLASSES"

# Clean up temporary file
rm css_classes.txt