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
            fee: 0.01 ether,
            expiry: block.timestamp + 1 hours,
            conditionType: keccak256("HTLC"),
            conditionCommitment: keccak256("secret"),
            applicationCommitment: keccak256("app"),
            escrowCommitment: keccak256("escrow"),
            channelNonce: 1
        });
    }

    function _lockId(ConditionalLock memory lock) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            lock.channelId, lock.initiator, lock.responder, lock.assetId,
            lock.amount, lock.fee, lock.expiry, lock.conditionType,
            lock.conditionCommitment, lock.applicationCommitment,
            lock.escrowCommitment, lock.channelNonce
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

    // 1. Deploy contract, verify domainSeparator
    function test_domainSeparator() public view {
        bytes32 expected = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("AgentOffchainConditionalSettlement"),
            keccak256("1"),
            block.chainid,
            address(acs)
        ));
        assertEq(acs.domainSeparator(), expected);
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

    // 9. supportsConditionType for all 6 canonical types
    function test_supportsConditionType_canonical() public view {
        assertTrue(acs.supportsConditionType(keccak256("HTLC")));
        assertTrue(acs.supportsConditionType(keccak256("ORACLE_ATTESTATION")));
        assertTrue(acs.supportsConditionType(keccak256("ZK_PROOF")));
        assertTrue(acs.supportsConditionType(keccak256("MULTISIG")));
        assertTrue(acs.supportsConditionType(keccak256("TIMELOCK")));
        assertTrue(acs.supportsConditionType(keccak256("COMPOSITE")));
    }

    // 10. supportsConditionType false for random
    function test_supportsConditionType_unknown() public view {
        assertFalse(acs.supportsConditionType(keccak256("RANDOM_GARBAGE")));
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

    // 13. ORACLE_ATTESTATION end-to-end
    function test_oracleAttestation_e2e() public {
        ConditionalLock memory lock = _defaultLock();
        lock.conditionType = keccak256("ORACLE_ATTESTATION");
        lock.conditionCommitment = keccak256("price>2000");
        bytes32 lid = _lockId(lock);

        acs.createLock(lock);
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Locked));

        SettlementProofRef memory proofRef = SettlementProofRef({
            channelId: CHANNEL,
            lockId: lid,
            proofType: keccak256("ORACLE_ATTESTATION"),
            settlementRoot: keccak256("oracle-root"),
            proofDigest: keccak256("oracle-digest"),
            verifier: address(verifier),
            auxDataHash: bytes32(0)
        });

        acs.settleConditional(CHANNEL, lock, proofRef, abi.encode("oracle says yes"));
        assertEq(uint8(acs.lockStatus(CHANNEL, lid)), uint8(IAgentConditionalSettlementExtension.LockStatus.Settled));
    }
}
