# ERC-8203: Agent Off-Chain Conditional Settlement

> Minimal settlement envelope for autonomous agents. Lock funds with conditions, prove completion off-chain, settle on-chain only when there's a dispute. Happy path is zero gas.

[![CI](https://github.com/Aboudjem/erc-8203-ref/actions/workflows/test.yml/badge.svg)](https://github.com/Aboudjem/erc-8203-ref/actions/workflows/test.yml)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-blue)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ERC-8203](https://img.shields.io/badge/ERC-8203-purple)](https://ethereum-magicians.org/t/erc-8203-agent-off-chain-conditional-settlement-extension-interface/28041)

---

## The Problem

AI agents are transacting on-chain. 85,000+ agents registered via ERC-8004. Billions in agent-to-agent payments ahead.

But there's no standard way for agents to settle conditional obligations. Today:

- **On-chain settlement per transaction** -- costs ~$443k/day for 1M agent interactions on L1
- **No shared envelope** -- every framework invents its own lock/prove/settle flow
- **No proof flexibility** -- settling an HTLC requires a specific proof format, can't use a ZK proof or oracle attestation instead

Stripe launched their centralized Machine Payments Protocol on March 18, 2026. The decentralized alternative needs a standard.

## The Solution

ERC-8203 adds a **conditional settlement extension** to state channel frameworks like ERC-7824.

```
Agent A                          Agent B
   |                                |
   |-- Lock funds with condition -->|
   |                                |
   |   [off-chain work happens]     |
   |                                |
   |<-- Proof of completion --------|
   |                                |
   |-- Verify proof, release funds  |
   |                                |
   [zero gas in happy path]
```

Three structs. Five functions. That's the whole interface.

## How It Works

### Orthogonal Taxonomy

ERC-8203's core insight: **what** needs to be proven and **how** it's proven are independent concerns.

```
                    PROOF TYPES (verification pathway)
                    +-----------+---------+--------+-----------+------+
                    | RECEIPT   | ZK      | ORACLE | MULTISIG  | TEE  |
                    | ROOT      | PROOF   | ATTEST | ATTEST    | ATT  |
     +--------------+-----------+---------+--------+-----------+------+
C    | HTLC         |     *     |    *    |   *    |     *     |  *   |
O    | TIMELOCK     |     *     |    *    |   *    |     *     |  *   |
N    | THRESHOLD    |     *     |    *    |   *    |     *     |  *   |
D    | EXTERNAL     |     *     |    *    |   *    |     *     |  *   |
     | COMPOSITE    |     *     |    *    |   *    |     *     |  *   |
     +--------------+-----------+---------+--------+-----------+------+

     Any cell is a valid combination. No artificial coupling.
```

An HTLC settled with a ZK proof. A timelock verified by an oracle. A composite condition proven via merkle receipt. All valid.

### Settlement Flow

```
createLock()           -- Agent locks funds with a condition + host-state binding
settleConditional()    -- Counterparty submits proof, funds release if valid
refundConditional()    -- Lock expired? Initiator gets funds back automatically
lockStatus()           -- On-chain view of lock state (Locked/Settled/Refunded)
supportsConditionType()-- Can this contract handle HTLC? TIMELOCK? COMPOSITE?
supportsProofType()    -- Can it verify ZK proofs? Oracle attestations? TEE?
```

### Key Design Decisions

| Decision | Why |
|----------|-----|
| **Mandatory host-state binding** | `hostStateHash` prevents cross-host replay attacks |
| **ERC-5267 domain discovery** | Standard `eip712Domain()` instead of custom `domainSeparator()` |
| **Timestamp-based expiry** | `block.timestamp` not block numbers. Predictable across chains |
| **Verifier as address** | Pluggable on-chain verifier contracts. Swap verification strategies per protocol |
| **No RELAY_CLAIM proof type** | Relay fees handled via `maxRelayFee` field. Cleaner separation |
| **Off-chain happy path** | Zero gas when both parties agree. On-chain only for disputes |

---

## Quick Start

```bash
git clone https://github.com/Aboudjem/erc-8203-ref.git
cd erc-8203-ref
forge install
forge build
forge test -vvv
```

## Project Structure

```
src/
  IAgentConditionalSettlement.sol   -- Interface: 3 structs, 5 functions, 2 events
  AgentConditionalSettlement.sol    -- Reference implementation
  MockProofVerifier.sol             -- Mock verifier for testing
test/
  AgentConditionalSettlement.t.sol  -- 24 test cases
```

## Test Coverage

| Category | Tests | What's Verified |
|----------|-------|-----------------|
| **Core lifecycle** | 1-8 | Create, settle, refund, double-settle prevention, expiry enforcement |
| **Condition types** | 9-10 | All 5 canonical types supported, old types rejected |
| **Proof types** | 13-14 | All 5 proof types discoverable, RELAY_CLAIM rejected |
| **Host-state binding** | 15-17 | Zero rejected, mismatch rejected, valid settle passes |
| **Relay fee paths** | 18-19 | `maxRelayFee > 0` (relay pays gas) and `== 0` (meta-tx) |
| **Cross combos** | 20-24 | HTLC+ZK, TIMELOCK+ORACLE, THRESHOLD+MULTISIG, EXTERNAL+TEE, COMPOSITE+RECEIPT |
| **Standards** | 11-12 | ERC-165 detection, lockId derivation, ERC-5267 domain |

```
24 passed | 0 failed | 0 skipped
```

---

## Where ERC-8203 Fits

```
+------------------+     +------------------+     +-------------------+
|    ERC-8004      |     |    ERC-8183      |     |    ERC-7824       |
|  Agent Identity  |     | Agentic Commerce |     | State Channels    |
|  & Reputation    |     |   (Job Escrow)   |     |   Framework       |
+--------+---------+     +--------+---------+     +---------+---------+
         |                        |                         |
         |    WHO is transacting  |  WHAT is the job        |  WHERE state lives
         |                        |                         |
         +------------+-----------+-----------+-------------+
                      |                       |
              +-------v-----------------------v-------+
              |           ERC-8203                     |
              |  Conditional Settlement Extension      |
              |                                        |
              |  HOW agents lock, prove, and settle    |
              +----------------------------------------+
```

## Related Standards

| Standard | Relationship |
|----------|-------------|
| [ERC-8203 spec](https://ethereum-magicians.org/t/erc-8203-agent-off-chain-conditional-settlement-extension-interface/28041) | The standard this implements |
| [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) | Agent identity/reputation. WHO is transacting |
| [ERC-8183](https://eips.ethereum.org/EIPS/eip-8183) | Agentic commerce. Job escrow for discrete work |
| [ERC-7824](https://ethereum-magicians.org/t/erc-7824-state-channels-framework/22566) | State channel framework. Host for conditional locks |
| [ERC-5267](https://eips.ethereum.org/EIPS/eip-5267) | EIP-712 domain discovery |

---

## Status

Reference implementation for spec clarity.

**Not audited. Not for production use without review.**

Matches the March 25, 2026 spec revision (orthogonal taxonomy).

## License

MIT
