// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SettlementProofRef} from "./IAgentConditionalSettlement.sol";

interface IProofVerifier {
    function verify(SettlementProofRef calldata proofRef, bytes calldata proof) external view returns (bool);
}

contract MockProofVerifier is IProofVerifier {
    bool public acceptAll = true;

    function setAcceptAll(bool _acceptAll) external {
        acceptAll = _acceptAll;
    }

    function verify(SettlementProofRef calldata, bytes calldata) external view override returns (bool) {
        return acceptAll;
    }
}
