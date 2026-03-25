// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AgentConditionalSettlement} from "../src/AgentConditionalSettlement.sol";
import {MockProofVerifier} from "../src/MockProofVerifier.sol";
import {IAgentConditionalSettlementExtension, ConditionalLock, SettlementProofRef} from "../src/IAgentConditionalSettlement.sol";

contract AgentConditionalSettlementTest is Test {
    AgentConditionalSettlement acs;
    MockProofVerifier verifier;

    bytes32 constant CHANNEL = keccak256("test-channel");
    address constant INITIATOR = address(0xA);
    address constant RESPONDER = address(0xB);
    bytes32 constant ASSET = keccak256("ETH");
    bytes32 constant HOST_STATE = keccak256("host-state-L1");

    function setUp() public {
        acs = new AgentConditionalSettlement();
        verifier = new MockProofVerifier();
    }

    function _defaultLock() internal view returns (ConditionalLock memory) {
        return ConditionalLock({
            channelId: CHANNEL,
            initiator: INITIATOR,
            responder: RESPONDER,
            assetId: ASSET,
            amount: 1 ether,
            maxRelayFee: 0.01 ether,
            expiry: block.timestamp + 1 hours,
            conditionType: keccak256("HTLC"),
            conditionCommitment: keccak256("secret"),
            applicationCommitment: keccak256("app"),
            escrowCommitment: keccak256("escrow"),
            hostStateHash: HOST_STATE,
            channelNonce: 1
        });
    }

    function _lockId(ConditionalLock memory lock) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            lock.channelId, lock.initiator, lock.responder, lock.assetId,
            lock.amount, lock.maxRelayFee, lock.expiry, lock.conditionType,
            lock.conditionCommitment, lock.applicationCommitment,
            lock.escrowCommitment, lock.hostStateHash, lock.channelNonce
        ));
    }

    function _defaultProofRef(ConditionalLock memory lock) internal view returns (SettlementProofRef memory) {
        return SettlementProofRef({
            channelId: CHANNEL,
            lockId: _lockId(lock),
            proofType: keccak256("RECEIPT_ROOT"),
            settlementRoot: keccak256("root"),
            proofDigest: keccak256("digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });
    }

    // ========== Core tests ==========

    // 1. ERC-5267 eip712Domain (replaces custom domainSeparator)
    function test_eip712Domain() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,
        ) = acs.eip712Domain();
        assertEq(fields, hex"0f");
        assertEq(keccak256(bytes(name)), keccak256("AgentConditionalSettlement"));
        assertEq(keccak256(bytes(version)), keccak256("1"));
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(acs));
    }

    // 2. Create lock, verify lockStatus returns Locked
    function test_createLock() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Locked));
    }

    // 3. Settle lock with valid proof
    function test_settleConditional() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = _defaultProofRef(lock);

        vm.expectEmit(true, true, true, true);
        emit IAgentConditionalSettlementExtension.ConditionalLockSettled(
            CHANNEL, lid, proofRef.proofType, proofRef.proofDigest
        );
        acs.settleConditional(CHANNEL, lock, proofRef, "");

        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 4. Settle lock with invalid proof
    function test_settleConditional_invalidProof() public {
        ConditionalLock memory lock = _defaultLock();
        acs.createLock(lock);
        verifier.setAcceptAll(false);

        SettlementProofRef memory proofRef = _defaultProofRef(lock);
        vm.expectRevert("proof invalid");
        acs.settleConditional(CHANNEL, lock, proofRef, "");
    }

    // 5. Settle already-settled lock
    function test_settleConditional_alreadySettled() public {
        ConditionalLock memory lock = _defaultLock();
        acs.createLock(lock);
        SettlementProofRef memory proofRef = _defaultProofRef(lock);
        acs.settleConditional(CHANNEL, lock, proofRef, "");

        vm.expectRevert("not locked");
        acs.settleConditional(CHANNEL, lock, proofRef, "");
    }

    // 6. Refund lock after expiry
    function test_refundConditional() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        vm.warp(lock.expiry);

        vm.expectEmit(true, true, false, false);
        emit IAgentConditionalSettlementExtension.ConditionalLockRefunded(CHANNEL, lid);
        acs.refundConditional(CHANNEL, lid);

        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Refunded));
    }

    // 7. Refund lock before expiry
    function test_refundConditional_beforeExpiry() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        vm.expectRevert("not expired");
        acs.refundConditional(CHANNEL, lid);
    }

    // 8. Refund already-settled lock
    function test_refundConditional_alreadySettled() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);
        SettlementProofRef memory proofRef = _defaultProofRef(lock);
        acs.settleConditional(CHANNEL, lock, proofRef, "");

        vm.warp(lock.expiry);
        vm.expectRevert("not locked");
        acs.refundConditional(CHANNEL, lid);
    }

    // 9. supportsConditionType — orthogonal taxonomy (change 1)
    function test_supportsConditionType_canonical() public view {
        assertTrue(acs.supportsConditionType(keccak256("HTLC")));
        assertTrue(acs.supportsConditionType(keccak256("TIMELOCK")));
        assertTrue(acs.supportsConditionType(keccak256("THRESHOLD_APPROVAL")));
        assertTrue(acs.supportsConditionType(keccak256("EXTERNAL_ASSERTION")));
        assertTrue(acs.supportsConditionType(keccak256("COMPOSITE")));
    }

    // 10. supportsConditionType false for old/unknown types
    function test_supportsConditionType_unknown() public view {
        assertFalse(acs.supportsConditionType(keccak256("RANDOM_GARBAGE")));
        // Old types that no longer exist in condition taxonomy
        assertFalse(acs.supportsConditionType(keccak256("ORACLE_ATTESTATION")));
        assertFalse(acs.supportsConditionType(keccak256("ZK_PROOF")));
        assertFalse(acs.supportsConditionType(keccak256("MULTISIG")));
    }

    // 11. ERC-165 supportsInterface
    function test_supportsInterface() public view {
        assertTrue(acs.supportsInterface(type(IAgentConditionalSettlementExtension).interfaceId));
        assertTrue(acs.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(acs.supportsInterface(0xffffffff));
    }

    // 12. lockId derivation matches expected keccak256
    function test_lockIdDerivation() public view {
        ConditionalLock memory lock = _defaultLock();
        bytes32 expected = _lockId(lock);
        bytes32 actual = acs.deriveLockId(lock);
        assertEq(actual, expected);
    }

    // ========== New test vectors ==========

    // 13. supportsProofType discovery (change 3)
    function test_supportsProofType_all() public view {
        assertTrue(acs.supportsProofType(keccak256("RECEIPT_ROOT")));
        assertTrue(acs.supportsProofType(keccak256("ZK_PROOF")));
        assertTrue(acs.supportsProofType(keccak256("ORACLE_ATTESTATION")));
        assertTrue(acs.supportsProofType(keccak256("MULTISIG_ATTESTATION")));
        assertTrue(acs.supportsProofType(keccak256("TEE_ATTESTATION")));
    }

    // 14. supportsProofType false for removed RELAY_CLAIM (change 6)
    function test_supportsProofType_noRelayClaim() public view {
        assertFalse(acs.supportsProofType(keccak256("RELAY_CLAIM")));
        assertFalse(acs.supportsProofType(keccak256("RANDOM_GARBAGE")));
    }

    // 15. Host-state binding — zero hostStateHash rejected on createLock
    function test_hostStateBinding_zeroRejected() public {
        ConditionalLock memory lock = _defaultLock();
        lock.hostStateHash = bytes32(0);
        vm.expectRevert("host state required");
        acs.createLock(lock);
    }

    // 16. Host-state binding — mismatch rejected on settle
    function test_hostStateBinding_mismatchRejected() public {
        ConditionalLock memory lock = _defaultLock();
        acs.createLock(lock);

        // Tamper with hostStateHash before settling
        ConditionalLock memory tampered = _defaultLock();
        tampered.hostStateHash = keccak256("wrong-host-state");

        // lockId will differ because hostStateHash is in the hash, so we need
        // to manipulate at the storage level. Instead, test the zero-check path
        // on settle by creating a lock then calling settle with zeroed host state.
        // The deriveLockId will differ, so the lock won't be found (status=None).
        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: _lockId(tampered),
            proofType: keccak256("RECEIPT_ROOT"),
            settlementRoot: keccak256("root"),
            proofDigest: keccak256("digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        vm.expectRevert("not locked");
        acs.settleConditional(CHANNEL, tampered, proofRef, "");
    }

    // 17. Host-state binding — valid settle preserves binding
    function test_hostStateBinding_validSettle() public {
        ConditionalLock memory lock = _defaultLock();
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);
        SettlementProofRef memory proofRef = _defaultProofRef(lock);

        // Should not revert — hostStateHash matches
        acs.settleConditional(CHANNEL, lock, proofRef, "");
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 18. Relay fee path: maxRelayFee > 0
    function test_relayFee_nonZero() public {
        ConditionalLock memory lock = _defaultLock();
        lock.maxRelayFee = 0.05 ether;
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("RECEIPT_ROOT"),
            settlementRoot: keccak256("root"),
            proofDigest: keccak256("digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, "");
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 19. Relay fee path: maxRelayFee == 0 (direct settlement, no relay)
    function test_relayFee_zero() public {
        ConditionalLock memory lock = _defaultLock();
        lock.maxRelayFee = 0;
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("RECEIPT_ROOT"),
            settlementRoot: keccak256("root"),
            proofDigest: keccak256("digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, "");
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 20. Cross condition/proof: HTLC condition proven via ZK_PROOF
    function test_crossConditionProof_htlcViaZk() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("HTLC");
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("ZK_PROOF"), // different from condition type
            settlementRoot: keccak256("zk-root"),
            proofDigest: keccak256("zk-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("zk proof data"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 21. Cross condition/proof: TIMELOCK condition proven via ORACLE_ATTESTATION
    function test_crossConditionProof_timelockViaOracle() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("TIMELOCK");
        lock.conditionCommitment = keccak256("unlock-at-T");
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("ORACLE_ATTESTATION"),
            settlementRoot: keccak256("oracle-root"),
            proofDigest: keccak256("oracle-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("oracle says time passed"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 22. Cross condition/proof: THRESHOLD_APPROVAL condition proven via MULTISIG_ATTESTATION
    function test_crossConditionProof_thresholdViaMultisig() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("THRESHOLD_APPROVAL");
        lock.conditionCommitment = keccak256("3-of-5");
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("MULTISIG_ATTESTATION"),
            settlementRoot: keccak256("multisig-root"),
            proofDigest: keccak256("multisig-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("3 sigs"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 23. Cross condition/proof: EXTERNAL_ASSERTION condition proven via TEE_ATTESTATION
    function test_crossConditionProof_externalViaTee() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("EXTERNAL_ASSERTION");
        lock.conditionCommitment = keccak256("api-response-hash");
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("TEE_ATTESTATION"),
            settlementRoot: keccak256("tee-root"),
            proofDigest: keccak256("tee-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("tee attestation"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }

    // 24. Cross condition/proof: COMPOSITE condition proven via RECEIPT_ROOT
    function test_crossConditionProof_compositeViaReceipt() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("COMPOSITE");
        lock.conditionCommitment = keccak256("AND(htlc,timelock)");
        bytes32 lid = _lockId(lock);
        acs.createLock(lock);

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("RECEIPT_ROOT"),
            settlementRoot: keccak256("receipt-root"),
            proofDigest: keccak256("receipt-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("receipt proof"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }
}
