// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://arbiscan.io/address/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1#code
interface IWETH {
    function deposit() external payable;
}
