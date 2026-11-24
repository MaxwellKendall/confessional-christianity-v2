import path from 'path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  test: {
    include: ['test/**/*.test.ts', 'scripts/**/*.test.mjs'],
    // This suite is a Verify check on a shared build Mac where several agents
    // build at once (load average 20-40 on 10 cores). Tests that do real work
    // (the sitemap and entry indexes over every confession, scripts that spawn
    // git) take 0.3-0.5 s idle but over 5 s there, so vitest's 5 s / 10 s
    // defaults failed a different handful of correct tests on each run. A hung
    // test still fails, after 60 s (TKL-981).
    testTimeout: 60_000,
    hookTimeout: 60_000,
  },
});
