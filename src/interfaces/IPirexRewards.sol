// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IPirexRewards {
    function harvest()
        external
        returns (
            ERC20[] memory _producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        );
}
