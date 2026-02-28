// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
@title ISubAgentManagerModule
@author Lajos Deme, github.com/lajosdeme
@dev The SubAgentManagerModule includes management functions for sub-agents
 */
interface ISubAgentManagerModule {
    struct CallPermission {
        address target; // Target contract
        bytes4 selector; // Function selector
    }

    struct SubAgentConfig {
        bool active;
        uint256 createdAt;
        // a sub-agent level permissions nonce for disabling all permissions for an agent
        uint256 nonce;
    }

    struct SubAgentSpending {
        uint256 allowed;
        uint256 spent;
        uint256 timeInterval;
        uint256 lastUpdated;
    }

    error OnlySafe();
    error NotActiveSubAgent();
    error NotCreatedAgent();
    error SpendingLimitAlreadySet();
    error DepositNativeFailed();

    event CreatedSubAgent(address indexed subAgent);

    event SpendingLimitSet(
        address indexed subAgent,
        uint256 indexed allowed,
        uint256 indexed timeInterval
    );
    event SpendingReset(
        address indexed subAgent,
        uint256 indexed newPeriodStart
    );

    event UpdatedSpendingLimitAllowed(
        address indexed subAgent,
        uint256 indexed newAllowed
    );
    event UpdatedSpendingLimitTimeInterval(
        address indexed subAgent,
        uint256 newTimeInterval
    );

    event DepositedNative(address indexed subAgent, uint256 indexed amount);
    event WithdrewNative(address indexed subAgent, uint256 indexed amount);
    event DepositedERC20(
        address indexed subAgent,
        address indexed token,
        uint256 indexed amount
    );
    event WithdrewERC20(
        address indexed subAgent,
        address indexed token,
        uint256 indexed amount
    );

    event AddedPermissions(
        address indexed subAgent,
        CallPermission[] permissions
    );

    event DisabledPermissionsForAll();

    event DisabledAllPermissionsForOne(address indexed subAgent);

    event DisabledPermissionForOne(
        address indexed subAgent,
        CallPermission permission
    );

    event ChangedAgentIsActive(address indexed subAgent, bool indexed isActive);
}
