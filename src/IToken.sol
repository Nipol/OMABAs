// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

interface IToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}
