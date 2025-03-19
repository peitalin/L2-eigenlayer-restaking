/// <reference types="@testing-library/jest-dom" />

declare module '@testing-library/jest-dom/matchers' {
  import { expect } from 'vitest';
  const matchers: Record<string, any>;
  export default matchers;
}

declare namespace jest {
  interface Matchers<R> extends Testing.Matchers<R> {}
}

declare module '@testing-library/jest-dom/matchers' {
  const matchers: any;
  export default matchers;
}