// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISafe} from "@safe-global/safe-contracts/contracts/interfaces/ISafe.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/libraries/Enum.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Initializable} from "./external/Initializable.sol";

/**
@title SessionKeyModule
@author Lajos Deme, github.com/lajosdeme
@dev Session key management for ERC4337A agentic sub-accounts
 */
contract SessionKeyModule is Initializable {
    string public constant NAME = "SessionKey Module";
    string public constant VERSION = "1.0.0";

    address constant HYPT_FACTORY = 0x0000000000000000000000000000000000000888;

    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 private constant LIMIT_TYPEHASH =
        keccak256("Limit(address token,uint256 amount)");

    // Session key permission typehash - includes Limit array
    bytes32 private constant SESSION_KEY_TYPEHASH =
        keccak256(
            "SessionKey(address sessionKey,uint256 validAfter,uint256 validUntil,Limit[] limits,address targetContract,bytes4 functionSelector,uint256 nonce)Limit(address token,uint256 amount)"
        );

    address private constant GAS_TOKEN =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ANY_TOKEN =
        0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF; // Max address

    struct Limit {
        address token;
        uint256 amount;
    }

    struct TokenSpend {
        address token;
        uint256 balance;
        uint256 limit;
    }

    error OnlySafe();
    error OnlySessionKey();
    error SessionKeyIsRevoked();
    error SessionKeyNotYetValid();
    error SessionKeyExpired();
    error FunctionNotAllowed();
    error LimitExceeded(address);
    error ExecutionFailed();

    event SessionKeyRevoked(bytes32 indexed sessionKeyHash);

    event SessionKeyExecuted(
        address indexed sessionKey,
        address indexed targetContract,
        bytes4 indexed functionSelector
    );

    address public SAFE;

    // can be used to emergency revoke all active session keys
    uint256 public nonce;

    mapping(bytes32 => bool) public revoked;

    // keccak256(sessionKeyHash, limit token) to used limit amount
    mapping(bytes32 => uint256) public usedLimits;

    modifier onlySafe() {
        if (msg.sender != SAFE) {
            revert OnlySafe();
        }
        _;
    }

    function initialize(address _safe) external initializer {
        if (msg.sender != HYPT_FACTORY) {
            revert();
        }
        
        SAFE = _safe;
    }

    function executeWithSessionKey(
        uint256 value,
        bytes memory data,
        uint256 validAfter,
        uint256 validUntil,
        Limit[] calldata limits,
        address targetContract,
        bytes4 functionSelector,
        bytes memory signatures
    ) external returns (bool success) {
        bytes32 sessionHash = getSessionKeyHash(
            msg.sender,
            validAfter,
            validUntil,
            limits,
            targetContract,
            functionSelector
        );

        bytes32 typedDataHash = getTypedDataHash(
            msg.sender,
            validAfter,
            validUntil,
            limits,
            targetContract,
            functionSelector
        );

        ISafe(payable(SAFE)).checkSignatures(
            msg.sender,
            typedDataHash,
            signatures
        );

        _verifySessionKeyHash(
            functionSelector,
            validAfter,
            validUntil,
            sessionHash,
            data
        );

        // Check and update limits
        TokenSpend[] memory balancesBefore;

        if (!_hasUnlimitedPermission(limits)) {
            uint256 finalLength;
            balancesBefore = new TokenSpend[](limits.length);
            for (uint256 i = 0; i < limits.length; i++) {
                if (limits[i].amount != type(uint256).max) {
                    balancesBefore[i] = TokenSpend({
                        token: limits[i].token,
                        limit: limits[i].amount,
                        balance: limits[i].token == GAS_TOKEN
                            ? SAFE.balance
                            : IERC20(limits[i].token).balanceOf(SAFE)
                    });
                    finalLength++;
                }
            }
            if (finalLength < limits.length) {
                assembly {
                    mstore(balancesBefore, finalLength)
                }
            }
        }

        success = ISafe(payable(SAFE)).execTransactionFromModule(
            targetContract,
            value,
            data,
            Enum.Operation.Call
        );

        if (!success) {
            revert ExecutionFailed();
        }

        // validate spend limits
        if (!_hasUnlimitedPermission(limits)) {
            for (uint256 i = 0; i < balancesBefore.length; i++) {
                uint256 _balanceAfter = balancesBefore[i].token == GAS_TOKEN
                    ? SAFE.balance
                    : IERC20(balancesBefore[i].token).balanceOf(SAFE);
                uint256 _tokenSpent = balancesBefore[i].balance - _balanceAfter;

                if (_tokenSpent > 0) {
                    bytes32 _tokenLimitHash = keccak256(
                        abi.encode(sessionHash, balancesBefore[i].token)
                    );

                    uint256 _newTotal = usedLimits[_tokenLimitHash] +
                        _tokenSpent;

                    if (_newTotal > balancesBefore[i].limit) {
                        revert LimitExceeded(balancesBefore[i].token);
                    }

                    usedLimits[_tokenLimitHash] = _newTotal;
                }
            }
        }

        emit SessionKeyExecuted(msg.sender, targetContract, functionSelector);
    }

    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_SEPARATOR_TYPEHASH,
                    keccak256(bytes(NAME)),
                    keccak256(bytes(VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }

    function getSessionKeyHash(
        address sessionKey,
        uint256 validAfter,
        uint256 validUntil,
        Limit[] calldata limits,
        address targetContract,
        bytes4 functionSelector
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SESSION_KEY_TYPEHASH,
                    sessionKey,
                    validAfter,
                    validUntil,
                    hashLimits(limits),
                    targetContract,
                    functionSelector,
                    nonce
                )
            );
    }

    function getTypedDataHash(
        address sessionKey,
        uint256 validAfter,
        uint256 validUntil,
        Limit[] calldata limits,
        address targetContract,
        bytes4 functionSelector
    ) public view returns (bytes32) {
        bytes32 structHash = getSessionKeyHash(
            sessionKey,
            validAfter,
            validUntil,
            limits,
            targetContract,
            functionSelector
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator(), structHash)
            );
    }

    /**
     * @notice Revokes a session key by its hash
     * @dev Can only be called by the Safe itself
     * @param sessionHash The hash of the session to revoke
     */
    function revokeSessionByHash(bytes32 sessionHash) external onlySafe {
        revoked[sessionHash] = true;

        emit SessionKeyRevoked(sessionHash);
    }

    function revokeSession(
        address sessionKey,
        uint256 validAfter,
        uint256 validUntil,
        Limit[] calldata limits,
        address targetContract,
        bytes4 functionSelector
    ) external onlySafe {
        bytes32 sessionHash = getSessionKeyHash(
            sessionKey,
            validAfter,
            validUntil,
            limits,
            targetContract,
            functionSelector
        );

        revoked[sessionHash] = true;
        emit SessionKeyRevoked(sessionHash);
    }

    /**
     * @notice Increments the nonce, invalidating all existing session signatures
     * @dev Can only be called by the Safe itself - useful for emergency revocation of all sessions
     */
    function revokeAllSessions() external onlySafe {
        nonce++;
    }

    function hashLimit(Limit memory limit) public pure returns (bytes32) {
        return keccak256(abi.encode(LIMIT_TYPEHASH, limit.token, limit.amount));
    }

    /**
     * @notice Hashes an array of Limit structs
     */
    function hashLimits(Limit[] memory limits) public pure returns (bytes32) {
        bytes32[] memory limitHashes = new bytes32[](limits.length);
        for (uint256 i = 0; i < limits.length; i++) {
            limitHashes[i] = hashLimit(limits[i]);
        }
        return keccak256(abi.encodePacked(limitHashes));
    }

    function _verifySessionKeyHash(
        bytes4 functionSelector,
        uint256 validAfter,
        uint256 validUntil,
        bytes32 sessionHash,
        bytes memory data
    ) internal view {
        if (revoked[sessionHash]) {
            revert SessionKeyIsRevoked();
        }

        if (block.timestamp < validAfter) {
            revert SessionKeyNotYetValid();
        }

        if (block.timestamp > validUntil) {
            revert SessionKeyExpired();
        }

        // Validate function sig
        if (functionSelector != bytes4(0) && data.length >= 4) {
            bytes4 selector = bytes4(data);
            if (selector != functionSelector) {
                revert FunctionNotAllowed();
            }
        }
    }

    function _hasUnlimitedPermission(
        Limit[] memory limits
    ) internal pure returns (bool) {
        return (limits.length == 1 &&
            limits[0].token == ANY_TOKEN &&
            limits[0].amount == type(uint256).max);
    }
}
