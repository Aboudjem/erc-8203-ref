// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct ConditionalLock {
    bytes32 channelId;
    address initiator;
    address responder;
    bytes32 assetId;
    uint256 amount;
    uint256 fee;
    uint256 expiry;
    bytes32 conditionType;
    bytes32 conditionCommitment;
    bytes32 applicationCommitment;
    bytes32 escrowCommitment;
    uint256 channelNonce;
}

struct SettlementProofRef {
    bytes32 channelId;
    bytes32 lockId;
    bytes32 proofType;
    bytes32 settlementRoot;
    bytes32 proofDigest;
    address verifier;
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
    uint256 nonce;
}

interface IAgentConditionalSettlementExtension {
    enum LockStatus { None, Locked, Settled, Refunded }

    event ConditionalLockSettled(
        bytes32 indexed channelId,
        bytes32 indexed lockId,
        bytes32 indexed proofType,
        bytes32 proofDigest
    );
    event ConditionalLockRefunded(
        bytes32 indexed channelId,
        bytes32 indexed lockId
    );

    function settleConditional(
        bytes32 channelId,
        ConditionalLock calldata lock,
        SettlementProofRef calldata proofRef,
        bytes calldata proof
    ) external;

    function refundConditional(bytes32 channelId, bytes32 lockId) external;

    function lockStatus(bytes32 channelId, bytes32 lockId) external view returns (LockStatus);

    function supportsConditionType(bytes32 conditionType) external view returns (bool);

    function domainSeparator() external view returns (bytes32);
}
