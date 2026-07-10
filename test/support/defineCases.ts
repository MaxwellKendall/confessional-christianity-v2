import { test } from 'vitest';

export const defineCases = <T>(
  casesByName: Record<string, T>,
  assertCase: (testCase: T, caseName: string) => void | Promise<void>,
): void => {
  Object.entries(casesByName).forEach(([caseName, testCase]) => {
    test(caseName, () => assertCase(testCase, caseName));
  });
};
