// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
@title IHyptFactory
@author Lajos Deme, github.com/lajosdeme
@dev Interface for the HyptFactory precompile on the HyperAgent blockchain
 */
interface IHyptFactory {
    function createAgent(uint256 saltNonce) external returns (address);

    function createSubAgent(uint256 saltNonce) external returns (address);
}
