import { defineConfig, devices } from '@playwright/test';
import * as path from 'path';

/**
 * Playwright configuration for OneList UI testing.
 * PLAN-050: Playwright Testing Framework
 */

const authFile = path.join(__dirname, '.auth/user.json');

export default defineConfig({
  testDir: './tests',
  fullyParallel: false, // Run tests serially to avoid rate limiting
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1, // Single worker to avoid rate limiting
  reporter: 'html',

  use: {
    // Base URL for tests
    baseURL: process.env.TEST_BASE_URL || 'http://localhost:4000',

    // Collect trace on failure
    trace: 'on-first-retry',

    // Screenshot on failure
    screenshot: 'only-on-failure',
  },

  projects: [
    // Setup project - runs first to authenticate
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/,
    },
    // Main tests - depend on setup
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: authFile,
      },
      dependencies: ['setup'],
      testIgnore: /auth\.setup\.ts/,
    },
  ],

  // Run local dev server before tests (optional)
  // webServer: {
  //   command: 'mix phx.server',
  //   url: 'http://localhost:4000',
  //   reuseExistingServer: !process.env.CI,
  //   cwd: '..',
  // },
});
