import { testCalculateTokenLeafHash } from './rewards';

// Run the token leaf hash test
console.log("Running token leaf hash test...");
const tokenLeafTestResult = testCalculateTokenLeafHash();
console.log("Test complete. Result:", tokenLeafTestResult ? "SUCCESS" : "FAILURE");