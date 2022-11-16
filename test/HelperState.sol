// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PirexGmx} from "src/PirexGmx.sol";
import {PirexFees} from "src/PirexFees.sol";

contract HelperState {
    // PirexGmx reusable state
    uint256 internal feeMax;
    uint256 internal feeDenominator;
    PirexGmx.Fees[3] internal feeTypes;
    bytes32 internal delegationSpace;

    // PirexFees reusable state
    uint8 internal feePercentDenominator;
    uint8 internal maxTreasuryFeePercent;
    uint8 internal treasuryFeePercent;
    address internal treasury;
    address internal contributors;
}
