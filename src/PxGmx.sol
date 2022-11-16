// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PxERC20} from "src/PxERC20.sol";

contract PxGmx is PxERC20 {
    /**
        @param  _pirexRewards  address  PirexRewards contract address
    */
    constructor(address _pirexRewards)
        PxERC20(_pirexRewards, "Pirex GMX", "pxGMX", 18)
    {}

    /**
        @notice Burn tokens
        @param  from    address  Token owner
        @param  amount  uint256  Token burn amount
    */
    function burn(address from, uint256 amount)
        external
        override
        onlyRole(BURNER_ROLE)
    {}
}
