// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentConditionalSettlementExtension, ConditionalLock, SettlementProofRef} from "./IAgentConditionalSettlement.sol";
import {IProofVerifier} from "./MockProofVerifier.sol";

contract AgentConditionalSettlement is IAgentConditionalSettlementExtension {
    struct LockInfo {
        LockStatus status;
        uint256 expiry;
        bytes32 hostStateHash;
    }

    // channelId => lockId => LockInfo
    mapping(bytes32 => mapping(bytes32 => LockInfo)) internal _locks;

    // --- Condition types (proposition semantics) ---
    bytes32 constant COND_HTLC = keccak256("HTLC");
    bytes32 constant COND_TIMELOCK = keccak256("TIMELOCK");
    bytes32 constant COND_THRESHOLD_APPROVAL = keccak256("THRESHOLD_APPROVAL");
    bytes32 constant COND_EXTERNAL_ASSERTION = keccak256("EXTERNAL_ASSERTION");
    bytes32 constant COND_COMPOSITE = keccak256("COMPOSITE");

    // --- Proof types (verification pathway) ---
    bytes32 constant PROOF_RECEIPT_ROOT = keccak256("RECEIPT_ROOT");
    bytes32 constant PROOF_ZK_PROOF = keccak256("ZK_PROOF");
    bytes32 constant PROOF_ORACLE_ATTESTATION = keccak256("ORACLE_ATTESTATION");
    bytes32 constant PROOF_MULTISIG_ATTESTATION = keccak256("MULTISIG_ATTESTATION");
    bytes32 constant PROOF_TEE_ATTESTATION = keccak256("TEE_ATTESTATION");

    // ERC-5267 domain fields
    string constant EIP712_NAME = "AgentConditionalSettlement";
    string constant EIP712_VERSION = "1";

    function deriveLockId(ConditionalLock calldata lock) public pure returns (bytes32) {
        return keccak256(abi.encode(
            lock.channelId,
            lock.initiator,
            lock.responder,
            lock.assetId,
            lock.amount,
            lock.maxRelayFee,
            lock.expiry,
            lock.conditionType,
            lock.conditionCommitment,
            lock.applicationCommitment,
            lock.escrowCommitment,
            lock.hostStateHash,
            lock.channelNonce
        ));
    }

    function createLock(ConditionalLock calldata lock) external {
        bytes32 lockId = deriveLockId(lock);
        require(_locks[lock.channelId][lockId].status == LockStatus.None, "lock exists");
        require(lock.hostStateHash != bytes32(0), "host state required");
        _locks[lock.channelId][lockId] = LockInfo(LockStatus.Locked, lock.expiry, lock.hostStateHash);
    }

    function settleConditional(
        bytes32 channelId,
        ConditionalLock calldata lock,
        SettlementProofRef calldata proofRef,
        bytes calldata proof
    ) external override {
        bytes32 lockId = deriveLockId(lock);
        require(lock.channelId == channelId, "channelId mismatch");
        require(proofRef.channelId == channelId, "proofRef channelId mismatch");
        require(proofRef.lockId == lockId, "proofRef lockId mismatch");

        LockInfo storage info = _locks[channelId][lockId];
        require(info.status == LockStatus.Locked, "not locked");

        // Host-state binding validation (change 2)
        require(lock.hostStateHash != bytes32(0), "host state required");
        require(info.hostStateHash == lock.hostStateHash, "host state mismatch");

        require(IProofVerifier(proofRef.verifier).verify(proofRef, proof), "proof invalid");

        info.status = LockStatus.Settled;
        emit ConditionalLockSettled(channelId, lockId, proofRef.proofType, proofRef.proofDigest);
    }

    function refundConditional(bytes32 channelId, bytes32 lockId) external override {
        LockInfo storage info = _locks[channelId][lockId];
        require(info.status == LockStatus.Locked, "not locked");
        require(block.timestamp >= info.expiry, "not expired");

        info.status = LockStatus.Refunded;
        emit ConditionalLockRefunded(channelId, lockId);
    }

    /// @notice On-chain view only — does not reflect off-chain state (change 8)
    function lockStatus(bytes32 channelId, bytes32 lockId) external view override returns (LockStatus) {
        return _locks[channelId][lockId].status;
    }

    function supportsConditionType(bytes32 conditionType) external pure override returns (bool) {
        return conditionType == COND_HTLC
            || conditionType == COND_TIMELOCK
            || conditionType == COND_THRESHOLD_APPROVAL
            || conditionType == COND_EXTERNAL_ASSERTION
            || conditionType == COND_COMPOSITE;
    }

    /// @notice Symmetric discovery for proof types (change 3)
    function supportsProofType(bytes32 proofType) external pure override returns (bool) {
        return proofType == PROOF_RECEIPT_ROOT
            || proofType == PROOF_ZK_PROOF
            || proofType == PROOF_ORACLE_ATTESTATION
            || proofType == PROOF_MULTISIG_ATTESTATION
            || proofType == PROOF_TEE_ATTESTATION;
    }

    /// @notice ERC-5267 domain discovery (change 9)
    function eip712Domain()
        external
        view
        override
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (
            hex"0f", // 0b01111 = name, version, chainId, verifyingContract
            EIP712_NAME,
            EIP712_VERSION,
            block.chainid,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAgentConditionalSettlementExtension).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC-165
    }
}
