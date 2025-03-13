
//  Declaration for implicit type library
declare module 'testing-library__jest-dom' {
  // Re-export types from @testing-library/jest-dom
  export * from '@testing-library/jest-dom';
}

// Declaration for matchers
declare module '@testing-library/jest-dom/matchers' {
  const matchers: any;
  export default matchers;
}

// Declare global jest namespace
declare global {
  namespace jest {
    interface Matchers<R> {
      toBeInTheDocument(): R;
      toBeVisible(): R;
      toHaveTextContent(text: string | RegExp): R;
      // Add other matchers as needed
    }
  }
}