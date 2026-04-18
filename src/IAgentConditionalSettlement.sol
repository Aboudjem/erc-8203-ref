// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct ConditionalLock {
    bytes32 channelId;
    address initiator;
    address responder;
    bytes32 assetId; // deterministic mapping to host custody (change 5)
    uint256 amount;
    uint256 maxRelayFee; // relay fee field (change 6 — no RELAY_CLAIM proof type)
    uint256 expiry; // timestamp-based, not block number (change 4)
    bytes32 conditionType; // proposition semantics (change 1)
    bytes32 conditionCommitment;
    bytes32 applicationCommitment;
    bytes32 escrowCommitment;
    bytes32 hostStateHash; // host-state binding — mandatory (change 2)
    uint256 channelNonce;
}

struct SettlementProofRef {
    bytes32 channelId;
    bytes32 lockId;
    bytes32 proofType; // verification pathway — orthogonal to conditionType (change 1)
    bytes32 settlementRoot;
    bytes32 proofDigest;
    address verifier; // on-chain address, not bytes32 (change 4)
    bytes32 auxDataHash;
}

struct ClaimRelayRequest {
    bytes32 channelId;
    bytes32 lockId;
    bytes32 escrowCommitment;
    bytes32 outputCommitmentHash;
    uint256 maxRelayFee;
    uint256 deadline;
    bytes32 proofType;
    bytes32 proofDigest;
    address verifier; // verifier binding so relay cannot substitute on assembly (xrqin, post #15)
    bytes32 hostStateHash; // host-state binding for relay path too
    uint256 nonce;
}

// EIP-712 type string for off-chain signing of ClaimRelayRequest
// keccak256("ClaimRelayRequest(bytes32 channelId,bytes32 lockId,bytes32 escrowCommitment,bytes32 outputCommitmentHash,uint256 maxRelayFee,uint256 deadline,bytes32 proofType,bytes32 proofDigest,address verifier,bytes32 hostStateHash,uint256 nonce)")

interface IAgentConditionalSettlementExtension {
    enum LockStatus {
        None,
        Locked,
        Settled,
        Refunded
    }

    event ConditionalLockSettled(
        bytes32 indexed channelId, bytes32 indexed lockId, bytes32 indexed proofType, bytes32 proofDigest
    );
    event ConditionalLockRefunded(bytes32 indexed channelId, bytes32 indexed lockId);

    function settleConditional(
        bytes32 channelId,
        ConditionalLock calldata lock,
        SettlementProofRef calldata proofRef,
        bytes calldata proof
    ) external;

    function refundConditional(bytes32 channelId, bytes32 lockId) external;

    /// @notice On-chain view only (change 8)
    function lockStatus(bytes32 channelId, bytes32 lockId) external view returns (LockStatus);

    function supportsConditionType(bytes32 conditionType) external view returns (bool);

    /// @notice Symmetric discovery for proof types (change 3)
    function supportsProofType(bytes32 proofType) external view returns (bool);

    /// @notice ERC-5267 replaces custom domainSeparator() (change 9)
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
}
