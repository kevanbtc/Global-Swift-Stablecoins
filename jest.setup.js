// jest.setup.js
require('dotenv').config({ path: '.env.test' });
// Trim all environment variables loaded from .env.test to prevent whitespace issues
for (const key in process.env) {
  if (Object.prototype.hasOwnProperty.call(process.env, key) && typeof process.env[key] === 'string') {
    process.env[key] = process.env[key]?.trim();
  }
}
console.log("DEBUG: jest.setup.js: .env.test loaded and trimmed. XRPL_OPS_BONUS_SEED:", process.env.XRPL_OPS_BONUS_SEED);

// Extend Chai with Hardhat-specific matchers
// This is handled by hardhat-toolbox, but if issues persist, manual import might be needed.
// const chai = require('chai');
// const { withChai } = require('@nomicfoundation/hardhat-chai-matchers/dist/withChai');
// withChai(chai);
