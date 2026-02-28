// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
@title IProtocolRegistry
@author Lajos Deme, github.com/lajosdeme
@dev Interface for the HyptProtocolRegistry precompile on the HyperAgent blockchain
 */
interface IProtocolRegistry {
    function isProtocolRegistered(bytes32 protocolId) external view returns (bool);

    function getProtocolId(address protocolAddress, bytes32 protocolNameHash, uint256 salt) external view returns (bytes32);
}