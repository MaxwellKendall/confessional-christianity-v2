import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Design reference bundle, not app code.
    "docs/design-handoff/**",
  ]),
  {
    rules: {
      // The guest landing/session/start flow hydrates local-progress state
      // from effects (reading localStorage after mount); that's the pattern
      // this rule flags.
      "react-hooks/set-state-in-effect": "off",
    },
  },
]);

export default eslintConfig;
