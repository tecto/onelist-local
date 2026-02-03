import { test as setup, expect } from '@playwright/test';
import * as path from 'path';

const TEST_EMAIL = process.env.TEST_EMAIL || 'splntrb@onelist.my';
const TEST_PASS = process.env.TEST_PASS || 'test_password';
const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:4000';
const authFile = path.join(__dirname, '../.auth/user.json');

setup('authenticate', async ({ page }) => {
  await page.goto(`${BASE_URL}/login`);

  const emailInput = page.locator('#email');
  const passwordInput = page.locator('#password');
  const loginButton = page.locator('[data-test-id="login-button"]');

  await emailInput.waitFor({ state: 'visible' });
  await page.waitForTimeout(1000);

  await emailInput.click();
  await emailInput.fill(TEST_EMAIL);
  await passwordInput.click();
  await passwordInput.fill(TEST_PASS);

  await loginButton.click();
  await page.waitForURL(/\/(app|dashboard|watch)/, { timeout: 30000 });

  // Save signed-in state
  await page.context().storageState({ path: authFile });
});
