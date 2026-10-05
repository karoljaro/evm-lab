# evm-lab
A hands-on Solidity and EVM lab for smart contract development, testing, governance, and security experiments.

Uses Hardhat 3, Solidity 0.8.37, TypeScript 6, and viem. Bun manages
dependencies and runs package scripts; Hardhat and its TypeScript test runner
execute on Node.js.

## Getting started

```bash
bun install --frozen-lockfile
bun run check
```

`check` builds the contracts before checking TypeScript types and running both
test suites. Hardhat generates contract types in `artifacts/`, which is included
in `tsconfig.json` and excluded from git.

## Example contract and tests

- `contracts/Counter.sol`: a counter with increment events and a custom error.
- `contracts/Counter.t.sol`: Solidity unit tests, overflow checks, and fuzzing.
- `test/Counter.ts`: TypeScript integration tests using `node:test`, viem
  assertions, and fixtures that restore blockchain state between tests.

```bash
bun run test:solidity
bun run test:typescript
bun run test:production
bun run test:coverage
```

`test:production` runs the tests with the optimized production build profile.
`test:coverage` collects Solidity coverage from both test suites.
