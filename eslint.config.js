import globals from 'globals';
import path from 'path';
import { fileURLToPath } from 'url';

// __dirname equivalent for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load plugins and configs directly
import tseslintPlugin from '@typescript-eslint/eslint-plugin';
import tseslintParser from '@typescript-eslint/parser';
import js from '@eslint/js';
import prettierPlugin from 'eslint-plugin-prettier';
import prettierConfig from 'eslint-config-prettier';

export default [
  // 1. Global ignores
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'apps/**',
      'typechain-types/**'
    ],
  },

  // 2. Base JS rules
  {
    files: ['**/*.js', '**/*.ts', '**/*.tsx'],
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.mocha,
      },
    },
    rules: {
      ...js.configs.recommended.rules,
    }
  },

  // 3. TypeScript rules
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: tseslintParser,
      parserOptions: {
        ecmaVersion: 2020,
        sourceType: "module",
        project: ['./tsconfig.eslint.json'],
        tsconfigRootDir: __dirname,
      },
    },
    plugins: {
      '@typescript-eslint': tseslintPlugin,
      'prettier': prettierPlugin,
    },
    rules: {
      ...tseslintPlugin.configs.recommended.rules, // Directly include recommended rules
      ...prettierConfig.rules,
      "prettier/prettier": "error",
      "@typescript-eslint/no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
      "@typescript-eslint/explicit-module-boundary-types": "off",
      "@typescript-eslint/no-explicit-any": "off",
      "no-console": "warn",
      "no-debugger": "warn"
    },
  }
];
