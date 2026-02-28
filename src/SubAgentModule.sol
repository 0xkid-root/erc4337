// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ISafe} from "@safe-global/safe-contracts/contracts/interfaces/ISafe.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/libraries/Enum.sol";
import {SubAgentManagerModule} from "./SubAgentManagerModule.sol";
import {Safe4337Module} from "./external/Safe4337Module.sol";
import {CalldataDecoder} from "./libraries/CalldataDecoder.sol";
import {ISubAgentModule} from "./interfaces/ISubAgentModule.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Initializable} from "./external/Initializable.sol";

/**
@title SubAgentModule
@author Lajos Deme, github.com/lajosdeme
@dev ERC4337A agentic sub-accounts
 */
contract SubAgentModule is Safe4337Module, ISubAgentModule {
    using CalldataDecoder for bytes;
    string public constant NAME = "SubAgent Module";
    string public constant VERSION = "1.0.0";

    address public SAFE;
    address public PRIMARY_SAFE;
    SubAgentManagerModule public MANAGER_MODULE;

    modifier onlyPrimarySafe() {
        if (msg.sender != PRIMARY_SAFE) {
            revert NotPrimarySafe();
        }
        _;
    }

    /**
     * @notice Constructor sets up the module with references to primary safe and manager
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     * @param _primarySafe Address of the primary Safe that controls this sub-agent
     * @param _manager Address of the SubAgentManagerModule
     */
    function initialize(
        address _entryPoint,
        address _safe,
        address _primarySafe,
        address _manager
    ) external initializer {
        initialize_Safe4337(_entryPoint);

        require(_primarySafe != address(0), "Invalid primary safe");
        require(_manager != address(0), "Invalid manager");

        SAFE = _safe;
        PRIMARY_SAFE = _primarySafe;
        MANAGER_MODULE = SubAgentManagerModule(_manager);

        emit SubAgentModuleSetup(_safe, _primarySafe, _manager);
    }

    /**
     * @notice Validates a user operation (ERC-4337 required function)
     * @dev Combines Safe's native signature validation with manager permission validation
     * @param userOp The user operation to validate
     * @param missingAccountFunds Amount of funds missing for the operation
     * @return validationData Validation result (0 = valid, 1 = invalid, or packed time range)
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 missingAccountFunds
    )
        external
        override
        onlySupportedEntryPoint
        returns (uint256 validationData)
    {
        address payable safeAddress = payable(userOp.sender);
        // The entry point address is appended to the calldata by the Safe in the `FallbackManager` contract,
        // following ERC-2771. Because of this, the relayer may manipulate the entry point address, therefore
        // we have to verify that the sender is the Safe specified in the userOperation.
        if (safeAddress != msg.sender || safeAddress != SAFE) {
            revert InvalidCaller();
        }

        // We check the execution function signature to make sure the entry point can't call any other function
        // and make sure the execution of the user operation is handled by the module
        bytes4 selector = bytes4(userOp.callData);
        if (
            selector != this.executeUserOp.selector &&
            selector != this.executeUserOpWithErrorString.selector
        ) {
            revert UnsupportedExecutionFunction(selector);
        }

        // The userOp nonce is validated in the entry point (for 0.6.0+), therefore we will not check it again
        validationData = _validateSignatures(userOp);

        // Extract operation details and validate against manager permissions
        CalldataDecoder.SafeCall[] memory _calls = userOp
            .callData
            .decodeSafeCalls();

        uint256 managerValidationData;

        for (uint256 i = 0; i < _calls.length; i++) {
            managerValidationData = MANAGER_MODULE.validateSubAgentOp(
                safeAddress,
                _calls[i].target,
                _calls[i].value,
                _calls[i].data
            );
            if (managerValidationData == 1) {
                break;
            }
        }

        /*
        TODO: Implement calldata verification
                 (address target, uint256 value, bytes memory data) = _decodeCallData(
            userOp.callData
        ); */

        // We trust the entry point to set the correct prefund value, based on the operation params
        // We need to perform this even if the signature is not valid, else the simulation function of the entry point will not work.
        if (missingAccountFunds != 0) {
            // We intentionally ignore errors in paying the missing account funds, as the entry point is responsible for
            // verifying the prefund has been paid. This behaviour matches the reference base account implementation.
            ISafe(safeAddress).execTransactionFromModule(
                SUPPORTED_ENTRYPOINT,
                missingAccountFunds,
                "",
                Enum.Operation.Call
            );
        }

        validationData = validationData == 0 && managerValidationData == 0
            ? 0
            : 1;
    }

    function withdrawNative(uint256 amount) external onlyPrimarySafe {
        (bool success, ) = PRIMARY_SAFE.call{value: amount}("");

        if (!success) {
            revert WithdrawNativeFailed();
        }

        emit WithdrewNative(amount);
    }

    function onERC20Deposit(
        address token,
        uint256 amount
    ) external onlyPrimarySafe {
        uint256 currentApproved = IERC20(token).allowance(
            address(this),
            PRIMARY_SAFE
        );
        IERC20(token).approve(PRIMARY_SAFE, currentApproved + amount);

        emit OnERC20Deposit(token, amount);
    }

    function onERC20Withdraw(
        address token,
        uint256 amount
    ) external onlyPrimarySafe {
        uint256 currentApproved = IERC20(token).allowance(
            address(this),
            PRIMARY_SAFE
        );
        IERC20(token).approve(PRIMARY_SAFE, currentApproved - amount);

        emit OnERC20Withdraw(token, amount);
    }
}
