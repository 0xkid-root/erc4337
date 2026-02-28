// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISafe} from "@safe-global/safe-contracts/contracts/interfaces/ISafe.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/libraries/Enum.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IHyptFactory} from "./interfaces/IHyptFactory.sol";
import {ISubAgentManagerModule} from "./interfaces/ISubAgentManagerModule.sol";
import {ISubAgentModule} from "./interfaces/ISubAgentModule.sol";
import {SafeERC20} from "./external/SafeERC20.sol";
import {Initializable} from "./external/Initializable.sol";

/**
@title SubAgentManagerModule
@author Lajos Deme, github.com/lajosdeme
@dev Sub-account management for ERC4337A agentic accounts
 */
contract SubAgentManagerModule is ISubAgentManagerModule, Initializable {
    using SafeERC20 for IERC20;

    string public constant NAME = "SubAgentManager Module";
    string public constant VERSION = "1.0.0";

    // Special addresses for permission encoding
    address private constant ANY_CONTRACT =
        0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    address private constant NATIVE_TOKEN =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes4 private constant ANY_FUNCTION = 0xFFFFFFFF;

    IHyptFactory public constant HYPT_FACTORY =
        IHyptFactory(0x0000000000000000000000000000000000000888);

    address public SAFE;

    // a global nonce for disabling all permissions for all agents
    uint256 private permissionsNonce;

    mapping(address => SubAgentConfig) public subAgents;
    mapping(address => SubAgentSpending) public subAgentSpending;
    mapping(bytes32 => bool) public subAgentAllowedCalls; // keccak256(target, selector) => allowed

    modifier onlySafe() {
        if (msg.sender != SAFE) {
            revert OnlySafe();
        }
        _;
    }

    modifier onlyForActiveSubAgent(address subAgent) {
        if (!subAgents[subAgent].active || subAgents[subAgent].createdAt == 0) {
            revert NotActiveSubAgent();
        }
        _;
    }

    modifier onlyForCreatedAgent(address subAgent) {
        if (subAgents[subAgent].createdAt == 0) {
            revert NotCreatedAgent();
        }
        _;
    }

    function initialize(address _safe) external initializer {
        if (msg.sender != address(HYPT_FACTORY)) {
            revert();
        }
        SAFE = _safe;
    }

    function validateSubAgentOp(
        address subAgent,
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        onlyForActiveSubAgent(subAgent)
        returns (uint256 validationData)
    {
        bytes4 selector = bytes4(0);
        if (data.length >= 4) {
            selector = bytes4(data);
        }

        if (!_isCallAllowed(subAgent, target, selector)) {
            return 1; // Call not permitted
        }

        if (!_validateAndUpdateSpending(subAgent, value)) {
            return 1;
        }

        return 0; // Valid
    }

    function createSubAgent(
        uint256 saltNonce
    ) external onlySafe returns (address subAgent) {
        subAgent = HYPT_FACTORY.createSubAgent(saltNonce);
        subAgents[subAgent] = SubAgentConfig({
            active: true,
            createdAt: block.timestamp,
            nonce: 1
        });

        emit CreatedSubAgent(subAgent);
    }

    function createSubAgent(
        uint256 saltNonce,
        CallPermission[] calldata callPermissions,
        SubAgentSpending calldata spendingLimit
    ) external onlySafe returns (address subAgent) {
        subAgent = HYPT_FACTORY.createSubAgent(saltNonce);
        subAgents[subAgent] = SubAgentConfig({
            active: true,
            createdAt: block.timestamp,
            nonce: 1
        });

        for (uint256 i = 0; i < callPermissions.length; i++) {
            bytes32 key = _getCallKey(
                subAgent,
                callPermissions[i].target,
                callPermissions[i].selector
            );
            subAgentAllowedCalls[key] = true;
        }

        subAgentSpending[subAgent] = spendingLimit;

        emit CreatedSubAgent(subAgent);
    }

    function addPermissions(
        address subAgent,
        CallPermission[] calldata callPermissions
    ) external onlySafe onlyForActiveSubAgent(subAgent) {
        for (uint256 i = 0; i < callPermissions.length; i++) {
            bytes32 key = _getCallKey(
                subAgent,
                callPermissions[i].target,
                callPermissions[i].selector
            );
            subAgentAllowedCalls[key] = true;
        }

        emit AddedPermissions(subAgent, callPermissions);
    }

    function disableAllPermissionsForAll() external onlySafe {
        permissionsNonce++;
        emit DisabledPermissionsForAll();
    }

    function disableAllPermissionsForOne(
        address subAgent
    ) external onlySafe onlyForActiveSubAgent(subAgent) {
        subAgents[subAgent].nonce++;

        emit DisabledAllPermissionsForOne(subAgent);
    }

    function disablePermissionForOne(
        address subAgent,
        CallPermission calldata permission
    ) external onlySafe {
        bytes32 key = _getCallKey(
            subAgent,
            permission.target,
            permission.selector
        );
        subAgentAllowedCalls[key] = false;

        emit DisabledPermissionForOne(subAgent, permission);
    }

    function changeAgentIsActive(
        address subAgent,
        bool isActive
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        subAgents[subAgent].active = isActive;

        emit ChangedAgentIsActive(subAgent, isActive);
    }

    function setSpendingLimit(
        address subAgent,
        uint256 allowed,
        uint256 timeInterval
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        if (subAgentSpending[subAgent].lastUpdated > 0) {
            revert SpendingLimitAlreadySet();
        }
        subAgentSpending[subAgent] = SubAgentSpending({
            allowed: allowed,
            spent: 0,
            timeInterval: timeInterval,
            lastUpdated: block.timestamp
        });

        emit SpendingLimitSet(subAgent, allowed, timeInterval);
    }

    function updateSpendingLimitAllowed(
        address subAgent,
        uint256 newAllowed
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        subAgentSpending[subAgent].allowed = newAllowed;

        emit UpdatedSpendingLimitAllowed(subAgent, newAllowed);
    }

    function updateSpendingLimitTimeInterval(
        address subAgent,
        uint256 newTimeInterval
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        subAgentSpending[subAgent].timeInterval = newTimeInterval;
        subAgentSpending[subAgent].lastUpdated = block.timestamp;

        emit UpdatedSpendingLimitTimeInterval(subAgent, newTimeInterval);
    }

    function depositNative(
        address subAgent
    ) external payable onlySafe onlyForCreatedAgent(subAgent) {
        (bool success, ) = subAgent.call{value: msg.value}("");
        if (!success) {
            revert DepositNativeFailed();
        }

        emit DepositedNative(subAgent, msg.value);
    }

    function withdrawNative(
        address subAgent,
        uint256 amount
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        ISubAgentModule(subAgent).withdrawNative(amount);

        emit WithdrewNative(subAgent, amount);
    }

    function depositERC20(
        address subAgent,
        address token,
        uint256 amount
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        IERC20(token).safeTransferFrom(SAFE, subAgent, amount);
        ISubAgentModule(subAgent).onERC20Deposit(token, amount);

        emit DepositedERC20(subAgent, token, amount);
    }

    function withdrawERC20(
        address subAgent,
        address token,
        uint256 amount
    ) external onlySafe onlyForCreatedAgent(subAgent) {
        IERC20(token).safeTransferFrom(subAgent, SAFE, amount);
        ISubAgentModule(subAgent).onERC20Withdraw(token, amount);

        emit WithdrewERC20(subAgent, token, amount);
    }

    function hasPermission(
        address subAgent,
        CallPermission calldata permission
    ) external view returns (bool) {
        if (!subAgents[subAgent].active) {
            return false;
        }

        return
            subAgentAllowedCalls[
                _getCallKey(subAgent, permission.target, permission.selector)
            ];
    }

    function _validateAndUpdateSpending(
        address subAgent,
        uint256 value
    ) internal returns (bool) {
        SubAgentSpending storage spending = subAgentSpending[subAgent];

        if (spending.allowed == 0) {
            return false;
        }

        if (spending.allowed == type(uint256).max) {
            return true;
        }

        uint256 currentSpent = spending.spent;
        bool periodExpired = false;

        if (spending.timeInterval > 0 && spending.lastUpdated > 0) {
            uint256 timeElapsed = block.timestamp - spending.lastUpdated;

            if (timeElapsed >= spending.timeInterval) {
                periodExpired = true;
                currentSpent = 0;
                emit SpendingReset(subAgent, block.timestamp);
            }
        }

        uint256 newTotal = currentSpent + value;

        if (newTotal > spending.allowed) {
            return false;
        }

        if (periodExpired || spending.lastUpdated == 0) {
            spending.spent = value;
            spending.lastUpdated = block.timestamp;
        } else {
            spending.spent = newTotal;
        }

        return true;
    }

    function _isCallAllowed(
        address subAgent,
        address target,
        bytes4 selector
    ) internal view returns (bool) {
        // wildcard for everything allowed
        if (
            subAgentAllowedCalls[
                _getCallKey(subAgent, ANY_CONTRACT, ANY_FUNCTION)
            ]
        ) {
            return true;
        }

        // all functions on contract allowed
        if (subAgentAllowedCalls[_getCallKey(subAgent, target, ANY_FUNCTION)]) {
            return true;
        }

        // function allowed on all contracts
        if (
            subAgentAllowedCalls[_getCallKey(subAgent, ANY_CONTRACT, selector)]
        ) {
            return true;
        }

        // regular check
        if (subAgentAllowedCalls[_getCallKey(subAgent, target, selector)]) {
            return true;
        }

        return false;
    }

    function _getCallKey(
        address subAgent,
        address target,
        bytes4 selector
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    subAgent,
                    target,
                    selector,
                    permissionsNonce,
                    subAgents[subAgent].nonce
                )
            );
    }
}
