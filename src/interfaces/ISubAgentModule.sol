// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

/**
@title ISubAgentModule
@author Lajos Deme, github.com/lajosdeme
@dev Interface for the sub-agent module
 */
interface ISubAgentModule {
    error ManagerValidationFailed();
    error InvalidSignature();
    error NotPrimarySafe();
    error WithdrawNativeFailed();

    event SubAgentModuleSetup(
        address indexed safe,
        address indexed primarySafe,
        address indexed manager
    );

    event WithdrewNative(uint256 indexed amount);

    event OnERC20Deposit(address indexed token, uint256 indexed amount);
    event OnERC20Withdraw(address indexed token, uint256 indexed amount);

    function withdrawNative(uint256 amount) external;

    function onERC20Deposit(address token, uint256 amount) external;

    function onERC20Withdraw(address token, uint256 amount) external;
}
