// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library CalldataDecoder {
    struct SafeCall {
        address target;
        uint256 value;
        bytes4 selector;
        bytes data;
    }

    // Safe ERC4337 Module function selectors
    bytes4 constant EXECUTE_USER_OP = 0x541d63c8; // executeUserOp(address,uint256,bytes,uint8)
    bytes4 constant EXECUTE_USER_OP_WITH_ERROR_STRING = 0x5ac0a0f9; // executeUserOpWithErrorString(address,uint256,bytes,uint8)

    // Safe multisend function selector
    bytes4 constant MULTI_SEND = 0x8d80ff0a; // multiSend(bytes)

    function decodeSafeCalls(bytes calldata callData) internal pure returns (SafeCall[] memory) {
        if (callData.length < 4) {
            return new SafeCall[](0);
        }

        bytes4 selector;
        if (callData.length >= 4) {
            assembly {
                selector := calldataload(callData.offset)
            }
        }

        // Handle Safe ERC4337 Module calls
        if (selector == EXECUTE_USER_OP || selector == EXECUTE_USER_OP_WITH_ERROR_STRING) {
            return decodeSafeExecuteUserOp(callData);
        }

        // Handle direct Safe calls (shouldn't happen with ERC4337 module but just in case)
        return decodeSingleCall(callData);
    }

    function decodeSafeExecuteUserOp(bytes calldata callData) internal pure returns (SafeCall[] memory) {
        // Skip function selector (4 bytes)
        bytes calldata data = callData[4:];

        // Decode executeUserOp(address to, uint256 value, bytes data, uint8 operation)
        (address to, uint256 value, bytes memory callBytes, uint8 operation) =
            abi.decode(data, (address, uint256, bytes, uint8));

        // If operation == 1, it's a delegateCall to multiSend
        if (operation == 1 && to != address(0)) {
            // This is a batch transaction using multiSend
            return decodeMultiSend(callBytes);
        } else {
            // Single transaction
            SafeCall[] memory calls = new SafeCall[](1);
            bytes4 functionSelector;
            if (callBytes.length >= 4) {
                assembly {
                    functionSelector := mload(add(callBytes, 0x20))
                }
            }

            calls[0] = SafeCall({target: to, value: value, selector: functionSelector, data: callBytes});

            return calls;
        }
    }

    function decodeMultiSend(bytes memory multiSendData) internal pure returns (SafeCall[] memory) {
        if (multiSendData.length < 4) {
            return new SafeCall[](0);
        }

        // Check if it's multiSend call
        bytes4 selector;
        if (multiSendData.length >= 4) {
            assembly {
                selector := mload(add(multiSendData, 0x20))
            }
        }
        if (selector != MULTI_SEND) {
            return new SafeCall[](0);
        }

        // Skip multiSend selector and decode the transactions bytes
        bytes memory encodedData = new bytes(multiSendData.length - 4);
        for (uint256 i = 0; i < encodedData.length; i++) {
            encodedData[i] = multiSendData[i + 4];
        }
        bytes memory transactionsData = abi.decode(encodedData, (bytes));

        return parseMultiSendTransactions(transactionsData);
    }

    function parseMultiSendTransactions(bytes memory transactions) internal pure returns (SafeCall[] memory) {
        // Count transactions first
        uint256 count = 0;
        uint256 i = 0;

        while (i < transactions.length) {
            if (i + 85 > transactions.length) break; // Minimum transaction size

            // Skip operation (1 byte) + address (20 bytes) + value (32 bytes)
            uint256 dataLength;
            assembly {
                dataLength := mload(add(add(transactions, 0x20), add(i, 53)))
            }
            i += 85 + dataLength; // Move to next transaction
            count++;
        }

        // Parse transactions
        SafeCall[] memory calls = new SafeCall[](count);
        i = 0;
        uint256 callIndex = 0;

        while (i < transactions.length && callIndex < count) {
            if (i + 85 > transactions.length) break;

            // Parse transaction structure:
            // operation: 1 byte
            // to: 20 bytes
            // value: 32 bytes
            // dataLength: 32 bytes
            // data: dataLength bytes

            address to;
            assembly {
                // Correct way to extract 20-byte address after the operation byte
                to := div(mload(add(add(transactions, 0x21), i)), 0x1000000000000000000000000)
            }

            uint256 value;
            assembly {
                value := mload(add(add(transactions, 0x20), add(i, 21)))
            }

            uint256 dataLength;
            assembly {
                dataLength := mload(add(add(transactions, 0x20), add(i, 53)))
            }

            bytes memory data = new bytes(dataLength);
            for (uint256 j = 0; j < dataLength; j++) {
                data[j] = transactions[i + 85 + j];
            }

            bytes4 functionSelector;
            if (dataLength >= 4) {
                assembly {
                    functionSelector := mload(add(data, 0x20))
                }
            }

            calls[callIndex] = SafeCall({target: to, value: value, selector: functionSelector, data: data});

            i += 85 + dataLength;
            callIndex++;
        }

        return calls;
    }

    function decodeSingleCall(bytes calldata callData) internal pure returns (SafeCall[] memory) {
        require(callData.length >= 4, "Invalid calldata length");

        SafeCall[] memory calls = new SafeCall[](1);
        bytes4 selector = bytes4(callData[:4]);

        calls[0] = SafeCall({
            target: address(0),
            value: 0,
            selector: selector,
            data: callData[4:] // Only the parameters, not the selector
        });

        return calls;
    }
}
