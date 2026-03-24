// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentConditionalSettlementExtension, ConditionalLock, SettlementProofRef} from "./IAgentConditionalSettlement.sol";
import {IProofVerifier} from "./MockProofVerifier.sol";

contract AgentConditionalSettlement is IAgentConditionalSettlementExtension {
    struct LockInfo {
        LockStatus status;
        uint256 expiry;
    }

    // channelId => lockId => LockInfo
    mapping(bytes32 => mapping(bytes32 => LockInfo)) internal _locks;

    // Canonical condition types
    bytes32 constant HTLC = keccak256("HTLC");
    bytes32 constant ORACLE_ATTESTATION = keccak256("ORACLE_ATTESTATION");
    bytes32 constant ZK_PROOF = keccak256("ZK_PROOF");
    bytes32 constant MULTISIG = keccak256("MULTISIG");
    bytes32 constant TIMELOCK = keccak256("TIMELOCK");
    bytes32 constant COMPOSITE = keccak256("COMPOSITE");

    bytes32 immutable _domainSeparator;

    constructor() {
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("AgentOffchainConditionalSettlement"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function deriveLockId(ConditionalLock calldata lock) public pure returns (bytes32) {
        return keccak256(abi.encode(
            lock.channelId,
            lock.initiator,
            lock.responder,
            lock.assetId,
            lock.amount,
            lock.fee,
            lock.expiry,
            lock.conditionType,
            lock.conditionCommitment,
            lock.applicationCommitment,
            lock.escrowCommitment,
            lock.channelNonce
        ));
    }

    function createLock(ConditionalLock calldata lock) external {
        bytes32 lockId = deriveLockId(lock);
        require(_locks[lock.channelId][lockId].status == LockStatus.None, "lock exists");
        _locks[lock.channelId][lockId] = LockInfo(LockStatus.Locked, lock.expiry);
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

    function lockStatus(bytes32 channelId, bytes32 lockId) external view override returns (LockStatus) {
        return _locks[channelId][lockId].status;
    }

    function supportsConditionType(bytes32 conditionType) external pure override returns (bool) {
        return conditionType == HTLC
            || conditionType == ORACLE_ATTESTATION
            || conditionType == ZK_PROOF
            || conditionType == MULTISIG
            || conditionType == TIMELOCK
            || conditionType == COMPOSITE;
    }

    function domainSeparator() external view override returns (bytes32) {
        return _domainSeparator;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAgentConditionalSettlementExtension).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC-165
    }
}
