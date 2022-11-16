// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://arbiscan.io/address/0x321F653eED006AD1C29D174e17d96351BDe22649#code
interface IGlpManager {
    function getAums() external view returns (uint256[] memory);

    function vault() external view returns (address);

    function usdg() external view returns (address);
}
