// SPDX-License-Identifier: MIT

// https://arbiscan.io/address/0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE#code
pragma solidity 0.8.17;

interface IStakedGlp {
    function approve(address _spender, uint256 _amount) external returns (bool);

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);
}
