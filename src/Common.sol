// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct GlobalState {
    uint32 lastUpdate;
    uint224 lastSupply;
    uint256 rewards;
}

struct UserState {
    uint32 lastUpdate;
    uint224 lastBalance;
    uint256 rewards;
}
