import 'dotenv/config';
import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';

/**
 * E2E tests hit a real PostgreSQL database, never the dev one: by default the
 * `DATABASE_URL` database name with a `_test` suffix (e.g. `grocery_db_test`),
 * or `TEST_DATABASE_URL`. See `docs/owner-domain.md` for the one-time setup.
 */
function testDatabaseUrl(): string {
  if (process.env['TEST_DATABASE_URL']) {
    return process.env['TEST_DATABASE_URL'];
  }
  const url = new URL(process.env['DATABASE_URL'] ?? '');
  url.pathname = `${url.pathname}_test`;
  return url.toString();
}

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    // Suites share one database.
    fileParallelism: false,
    env: {
      DATABASE_URL: testDatabaseUrl(),
      JWT_SECRET: 'e2e-test-secret-not-for-production',
    },
  },
});
