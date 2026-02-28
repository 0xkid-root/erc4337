// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
@title IProtocol
@author Lajos Deme, github.com/lajosdeme
@dev Interface for that registered protocols implement
 */
interface IProtocol {
    function protocolNameHash() external view returns (bytes32);
    function protocolSalt() external view returns (uint256);
}