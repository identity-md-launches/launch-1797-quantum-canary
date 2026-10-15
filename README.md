# Quantum Canary (CANARY)

Quantum Canary is a fixed-supply ERC-20. Its constructor creates the entire supply
once and credits the immediate deployer. The implementation is
[`src/QuantumCanary.sol`](src/QuantumCanary.sol).

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `QuantumCanary` |
| Token name | `Quantum Canary` |
| Symbol | `CANARY` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None; ABI-encoded arguments are empty (`0x`) |
| Constructor payment | None; nonpayable constructor |
| Initial recipient | `msg.sender`, the immediate deployer |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

Deploy the creation bytecode built for `src/QuantumCanary.sol:QuantumCanary`.
There are no linked libraries, initializer calls, external constructor calls, or
application contracts. The constructor has no chain-specific dependencies.
`forge inspect src/QuantumCanary.sol:QuantumCanary bytecode` prints the creation
bytecode; the compiled ABI and bytecode are also in
`out/QuantumCanary.sol/QuantumCanary.json`.

During the IdentityMD launch, the factory is the immediate deployer and receives
all tokens. It performs the launch's distribution and pool setup separately. A
direct deployment credits the deploying wallet instead. A wrapper or script
contract that executes `new QuantumCanary()` receives the supply itself, so the
launch must use its intended factory. The token does not use `tx.origin`.

The separate launch process prepares `launch.json`, using contract identifier
`QuantumCanary`, empty constructor arguments, and the exact supply above. This
project does not create a manifest, sign transactions, or broadcast a deployment.

## Behavior and assumptions

The brief specifies a supply and metadata without custom transfer rules, so this
implements ordinary ERC-20 behavior using the vendored OpenZeppelin Contracts
v5.0.2 ERC-20 implementation. There are no taxes, transfer fees, rebases, burns,
later minting, pause controls, blacklists, ownership, or upgrade mechanisms.
The deployer has the same transfer rights as every other holder after deployment.

- `transfer` and `transferFrom` deliver exactly the requested amount and return
  `true` on success. Invalid operations revert with ERC-6093 custom errors.
- Zero-value transfers between valid addresses succeed and emit `Transfer`.
  Transfers to the zero address revert, including zero-value transfers.
- Only a holder or its approved spender can move that holder's tokens.
  `approve` replaces the allowance; approving zero revokes it.
- Finite allowances decrease when spent. `type(uint256).max` is an unlimited
  allowance and does not decrease. Failed transfers roll back allowance changes.
- `approve` emits `Approval`; `transferFrom` emits `Transfer` without an
  additional `Approval` event when it spends allowance. Integrations should read
  `allowance` for its current value.
- Transfers do not invoke recipient callbacks. Tokens sent to a contract unable
  to move them, including the token contract itself, cannot be recovered by an
  administrator. Ordinary ETH transfers are not accepted.

The standard is [ERC-20](https://eips.ethereum.org/EIPS/eip-20). Dependency versions,
download locations, and SHA-256 hashes for every vendored file are recorded in
[`DEPENDENCIES.json`](DEPENDENCIES.json). The OpenZeppelin subset includes its
complete import closure; forge-std v1.9.7 supplies test utilities. Both are ordinary
files in `lib/` with their upstream licenses. No dependency installation,
submodule, RPC, account, or API key is required to build or test.

## Build and checks

Run from the repository root with Foundry and the pinned Solidity compiler
available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x9c9eef904cd0b7fe3e2962d9a8e5dd265dabc8a36dbd01e2fd4963700d53d2a9 forge test
forge fmt --check
```

Foundry manages the compiler by version. The verifier supplies Solidity 0.8.26
offline; all Solidity dependencies are included here. The project does not enable
FFI or filesystem cheatcode permissions. Tests do not read or mutate environment
variables, use a fork, or depend on test order. The shell variable above selects
Foundry's reproducible fuzz seed.

Tests cover metadata, exact initial supply, the single mint event, CREATE2 factory
deployment, exact distribution/claim/pool transfer amounts, transfer and approval
events, zero/self transfers, allowance replacement and revocation, finite and
unlimited allowances, unauthorized spending, invalid addresses, insufficient
balances/allowances, rollback on failure, and absent administrative entrypoints.
Runtime checks reject DELEGATECALL, CALLCODE, and SELFDESTRUCT.

Four fuzz tests each run 512 cases. Two stateful invariants each run 128 sequences
of 64 calls, comparing balances and allowances with an independent model after
randomized transfers, approvals, and delegated transfers, while checking the
total supply remains constant. These counts are local verification settings in
`foundry.toml`, not on-chain parameters.

Local verification passed: `forge build`, `forge test` with the seed above, and
`forge fmt --check`. The test runner reported 31 passing tests (30 unit/fuzz tests
and one grouped invariant campaign), zero failures, and zero skips. The campaign
checked both invariant properties across 8,192 calls with zero reverts. Vendored
file hashes match `DEPENDENCIES.json`; the compiled token has no library link
references and its runtime is 1,752 bytes.

The local distribution fixture tests the token movements used during a launch.
It does not implement a Uniswap pool or demonstrate swap pricing. The supplied
protected launch tests depend on the network's separate factory/PoolManager
harness and manifest; that full integration remains the independent verifier's
responsibility.

## Operational responsibilities

Before launch, the network deployer must confirm the intended factory and chain,
review the creation bytecode and compiler settings, and use the supplied launch
economics in the separate manifest. Distribution, liquidity provisioning, and
pool administration belong to that launch system, not this token.

After launch, verify the deployed source/bytecode and check `name`, `symbol`,
`decimals`, `totalSupply`, and the constructor's `Transfer` event against the values
above. There are no owner settings, administrative keys, or post-deployment
initialization steps for the token.

Holders are responsible for custody, recipient selection, and spender approvals.
Prefer bounded approvals; when changing an existing allowance, revoke it and wait
for confirmation before setting a replacement to reduce the standard ERC-20
allowance replacement race. The contract cannot reverse completed transfers or
recover lost credentials.

The security review of this implementation focuses on the single internal mint,
authorization through balances/allowances, integer conservation, and the absence
of external calls and privileged entrypoints. Oracle, randomness, proxy, and
signature mechanisms are absent. Foundry tests and manual source review are local
checks, not an independent security audit. Slither and Mythril were not run. The
network's independent adversarial review and deployed-source verification remain
release responsibilities.
