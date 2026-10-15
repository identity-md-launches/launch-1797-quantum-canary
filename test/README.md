# Quantum Canary tests

The existing deployment and ERC-20 suite is supplemented by
`QuantumCanary.adversarial.t.sol`. It checks allowance replacement, revocation,
owner/spender isolation, transaction-origin isolation, repeated spending after a
balance refill, self-transfers, and zero/one/full-supply/uint256 boundary inputs.
Failure tests check the exact custom error and unchanged balances and allowances;
recovery tests then exercise a valid operation using the preserved state.

The ten fuzz properties run 1,000 cases each, configured inline in the test files.
They include transfer round trips and equivalence between split and combined
delegated transfers. Inputs are bounded instead of discarded with assumptions.

`QuantumCanary.invariant.t.sol` drives four funded actors through nine actions:
transfers, approvals, delegated transfers, revocations, excessive transfers,
excessive delegated transfers, transfers to zero, delegated transfers to zero,
and approvals of a zero spender. Actor indices may coincide to exercise self
transfers and self approvals. Finite approvals span the uint256 domain; unlimited
approvals use `type(uint256).max`.

After every action, three invariants check:

- The sum of all tracked balances and `totalSupply()` equal exactly `10^27`,
  each holder matches the independent ledger, and no supply leaks to untracked
  zero, handler, or token addresses.
- Every actor pair's allowance matches the authorization ledger. Rejected calls
  do not update that ledger, so these checks also enforce rollback.
- Name, symbol, decimals, and the initial-supply constant remain unchanged.

Inline settings select 256 sequences of 128 calls and fail on unexpected reverts.
Expected failures are explicitly matched; no handler action silently skips a call.
The handler is the only invariant target, keeping the holder set exhaustive.

Run from the repository root with the supplied dependencies and Solidity 0.8.26:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x9c9eef904cd0b7fe3e2962d9a8e5dd265dabc8a36dbd01e2fd4963700d53d2a9 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The output and cache flags keep generated files in disposable scratch space.
Delivered tests do not import anything from scratch or require a network, fork,
environment cheatcodes, or new dependencies. These tests cover the token; the
protected factory/Uniswap integration uses the verifier's separate launch harness.
