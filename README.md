# ERC-8203 Reference Implementation

Reference implementation for [ERC-8203: Agent Off-Chain Conditional Settlement Extension Interface](https://ethereum-magicians.org/t/erc-8203-agent-off-chain-conditional-settlement-extension-interface/28041).

ERC-8203 defines a minimal settlement envelope for autonomous agents operating over state channels. Agents lock funds with conditions, prove completion off-chain, and settle on-chain only when there's a dispute. Happy path is zero gas.

## What's in here

```
src/
  IAgentConditionalSettlement.sol   -- interface + structs (ConditionalLock, SettlementProofRef, ClaimRelayRequest)
  AgentConditionalSettlement.sol    -- reference implementation
  MockProofVerifier.sol             -- mock verifier for testing
test/
  AgentConditionalSettlement.t.sol  -- 24 tests covering all spec requirements
```

## Architecture

ERC-8203 separates **what** needs to be proven from **how** it's proven using two orthogonal axes:

**Condition types** (proposition semantics):
- `HTLC` -- hash time lock
- `TIMELOCK` -- time-based
- `THRESHOLD_APPROVAL` -- multisig-style threshold
- `EXTERNAL_ASSERTION` -- external oracle/entity
- `COMPOSITE` -- combination of above

**Proof types** (verification pathway):
- `RECEIPT_ROOT` -- merkle tree proof
- `ZK_PROOF` -- zero-knowledge proof
- `ORACLE_ATTESTATION` -- oracle attestation
- `MULTISIG_ATTESTATION` -- threshold signatures
- `TEE_ATTESTATION` -- trusted execution environment

Any condition can be proven via any proof type. An HTLC can be settled with a ZK proof. A TIMELOCK can be verified by an oracle attestation. No artificial coupling.

## Key design decisions

- **Mandatory host-state binding** -- `hostStateHash` prevents cross-host replay attacks
- **ERC-5267** -- uses `eip712Domain()` for domain discovery instead of custom `domainSeparator()`
- **Timestamp-based expiry** -- uses `block.timestamp`, not block numbers
- **Verifier as address** -- pluggable on-chain verifier contracts, not opaque bytes32
- **No RELAY_CLAIM proof type** -- relay fees handled separately via `maxRelayFee` field

## Quick start

```bash
# clone
git clone https://github.com/Aboudjem/erc-8203-ref.git
cd erc-8203-ref

# install deps
forge install

# build
forge build

# test
forge test -vvv
```

## Test coverage

24 tests covering:

| Category | Tests | What's tested |
|----------|-------|---------------|
| Core lifecycle | 1-8 | create, settle, refund, double-settle prevention, expiry enforcement |
| Condition types | 9-10 | all 5 canonical types supported, old types rejected |
| Proof types | 13-14 | all 5 proof types discovered, RELAY_CLAIM rejected |
| Host-state binding | 15-17 | zero rejected, mismatch rejected, valid settle |
| Relay fee paths | 18-19 | maxRelayFee > 0 and == 0 |
| Cross condition/proof | 20-24 | HTLC+ZK, TIMELOCK+ORACLE, THRESHOLD+MULTISIG, EXTERNAL+TEE, COMPOSITE+RECEIPT |
| Standards | 11-12 | ERC-165 interface detection, lockId derivation, ERC-5267 domain |

## Related standards

- [ERC-8203 spec](https://ethereum-magicians.org/t/erc-8203-agent-off-chain-conditional-settlement-extension-interface/28041) -- the standard this implements
- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) -- Trustless Agents (identity/reputation layer)
- [ERC-8183](https://eips.ethereum.org/EIPS/eip-8183) -- Agentic Commerce (job escrow, complements 8203)
- [ERC-7824](https://ethereum-magicians.org/t/erc-7824-state-channels-framework/22566) -- State Channels Framework (host framework)
- [ERC-5267](https://eips.ethereum.org/EIPS/eip-5267) -- EIP-712 Domain Discovery

## Status

This is a reference implementation for spec clarity. Not audited. Not for production use without review.

Matches the March 25, 2026 spec revision (orthogonal taxonomy, 10 changes).

## License

MIT
