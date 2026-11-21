import path from 'path';
import { defineConfig } from 'vitest/config';

// Evals call paid APIs, so they never run under `npm test`; `npm run eval:cards`.
export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '..', 'src'),
    },
  },
  test: {
    include: ['evals/**/*.eval.ts'],
    root: path.resolve(__dirname, '..'),
  },
});
