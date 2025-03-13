/// <reference types="vitest" />
import { defineConfig } from 'vitest/config';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/tests/setupTests.ts'],
    include: ['./src/tests/**/*.test.ts'],
    reporters: 'verbose',
    environmentMatchGlobs: [
      // Test files with DOM interaction need jsdom
      ['./src/tests/**', 'jsdom'],
      // Other tests can use node
      ['./src/**', 'node']
    ]
  },
  define: {
    'import.meta.vitest': 'undefined',
    'process.env.VITEST': 'true'
  }
});