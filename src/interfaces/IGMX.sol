// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://arbiscan.io/address/0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a#code
interface IGMX {
    function gov() external view returns (address);

    function balanceOf(address _account) external view returns (uint256);

    function mint(address _account, uint256 _amount) external;

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address _owner, address _spender)
        external
        view
        returns (uint256);
}
