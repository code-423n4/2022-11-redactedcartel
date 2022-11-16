// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://arbiscan.io/address/0x68863dDE14303BcED249cA8ec6AF85d4694dea6A#code
interface ITimelock {
    function admin() external view returns (address);

    function buffer() external view returns (uint256);

    function signalMint(address _token, address _receiver, uint256 _amount) external;

    function processMint(address _token, address _receiver, uint256 _amount) external;
}
