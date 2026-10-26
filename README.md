# EVM Lab

A hands-on Solidity and EVM lab for smart contract development, testing, governance, and security experiments.

The repository is used for Web3 / EVM laboratory work, with individual exercises implemented as reproducible automated tests instead of one-off manual Remix scenarios.

## Tooling

The project is intended to be installed and run primarily with [Bun](https://bun.sh/).

Main tools used in the repository:

- **Bun** — package management and project scripts
- **Hardhat 3** — Solidity compilation, local EVM networks, and contract testing
- **Viem** — typed interaction with deployed smart contracts
- **OpenZeppelin Contracts** — reusable and audited Solidity building blocks
- **TypeScript** — test and tooling code
- **Solidity 0.8.37** — smart contracts

## Getting started

Install dependencies:

```bash
bun install
```

Run the complete project check:

```bash
bun run check
```

The check runs contract compilation, TypeScript type checking, and the Hardhat test suite.

For direct Hardhat commands, use Bun as the launcher:

```bash
bunx hardhat build
bunx hardhat test
bunx hardhat clean
```

## Laboratory tasks

Laboratory exercises are represented as automated tests.

Each test documents a scenario, prepares the required blockchain state, performs the relevant transactions, and verifies the expected EVM / smart-contract behavior.

The implemented tasks can be found in the [`test/`](./test/) directory.

Current topics include:

- DAO governance with OpenZeppelin Governor
- ERC20Votes and delegated voting power
- proposal state transitions
- proposal rejection and execution rules
- configurable voting periods
- double-voting protection
- vote snapshots and checkpoints
- quorum and abstain votes
- proposal thresholds

This approach keeps the exercises reproducible and makes it possible to verify the complete laboratory work with a single command:

```bash
bun run check
```

## Development

After changing Solidity contracts, run:

```bash
bun run check
```

If Solidity artifacts need to be regenerated from scratch:

```bash
bunx hardhat clean
bun run check
```

## Notes

The repository is focused on practical Solidity and EVM experimentation. Tests are treated as executable documentation for the laboratory scenarios and edge cases being explored.

## Laboratory tasks

Laboratory exercises are implemented as automated tests and can be found
in the [`test/`](./test/) directory.

- [List 01](./docs/list-01/README.md)
- [Lista 02 — Mini Uniswap v1 i v2](./docs/list-02/README.md)

Lista 02 zawiera pule ERC20/ETH i ERC20/ERC20, tokeny LP, flash swapy,
testy bezpieczeństwa i pomiary gazu. Całość działa lokalnie przez Bun i Hardhat:

```bash
bun run test:list-02
bun run test:list-02:gas
```

Pełna dokumentacja po polsku, opis uproszczeń i odpowiedzi na cztery pytania
projektowe znajdują się w [dokumentacji listy 02](./docs/list-02/README.md).
