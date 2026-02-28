// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.30;

import {SafeL2} from "@safe-global/safe-contracts/contracts/SafeL2.sol";
import {IProtocolRegistry} from "./interfaces/IProtocolRegistry.sol";
import {IProtocol} from "./interfaces/IProtocol.sol";

/**
@title ERC477A
@author Lajos Deme, github.com/lajosdeme
@dev The main ERC4337A contract
 */
contract ERC4337A is SafeL2 {
    error NotAccount();
    error NotRegistered();
    error NotApproved();
    error EmptyAgentCardURI();

    struct ProtocolData {
        bytes data;
    }

    address constant REPUTATION_MODULE =
        0x0000000000000000000000000000000000000777;

    address constant FACTORY_MODULE =
        0x0000000000000000000000000000000000000888;

    bytes32 constant HYPERAGENT_PROTOCOL_ID = keccak256("hyperagent");

    IProtocolRegistry public constant PROTOCOL_REGISTRY =
        IProtocolRegistry(0x0000000000000000000000000000000000000555);

    // protocol approved until timestamp
    mapping(bytes32 => uint256) public protocolApprovedUntil;

    bytes32 internal constant HYPERAGENT_PROTOCOL_SLOT =
        keccak256(
            abi.encode(uint256(keccak256("HyperAgent.ERC4337A.self.slot")) - 1)
        ) & ~bytes32(uint256(0xff));

    string public agentCardURI;

    function protocolStateSlot(
        bytes32 protocolId
    ) private pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(protocolId, HYPERAGENT_PROTOCOL_SLOT));
    }

    function approveProtocolUntil(
        bytes32 _protocolId,
        uint256 _approvedUntil
    ) external {
        if (msg.sender != address(this)) {
            revert NotAccount();
        }

        if (!PROTOCOL_REGISTRY.isProtocolRegistered(_protocolId)) {
            revert NotRegistered();
        }

        if (_protocolId == HYPERAGENT_PROTOCOL_ID) {
            return;
        }

        protocolApprovedUntil[_protocolId] = _approvedUntil;
    }

    function isApprovedProtocol(
        bytes32 protocolId
    ) internal view returns (bool) {
        if (protocolId == HYPERAGENT_PROTOCOL_ID) {
            return true;
        }

        return protocolApprovedUntil[protocolId] > block.timestamp;
    }

    function setAgentCardUri(string calldata _agentCardUri) external {
        if (msg.sender != address(this)) {
            revert NotAccount();
        }

        if (bytes(_agentCardUri).length == 0) {
            revert EmptyAgentCardURI();
        }

        agentCardURI = _agentCardUri;
    }

    function getProtocolState(
        bytes32 protocolId
    ) internal pure returns (ProtocolData storage p) {
        bytes32 slot = protocolStateSlot(protocolId);

        assembly {
            p.slot := slot
        }
    }

    function writeToProtocolState(bytes calldata data) external {
        bytes32 protocolId;
        if (msg.sender == REPUTATION_MODULE) {
            protocolId = HYPERAGENT_PROTOCOL_ID;
        } else {
            protocolId = PROTOCOL_REGISTRY.getProtocolId(
                msg.sender,
                IProtocol(msg.sender).protocolNameHash(),
                IProtocol(msg.sender).protocolSalt()
            );
        }

        if (!isApprovedProtocol(protocolId)) {
            revert NotApproved();
        }

        ProtocolData storage _protocolState = getProtocolState(protocolId);
        _protocolState.data = data;
    }

    function readProtocolState(
        bytes32 protocolId
    ) external view returns (bytes memory) {
        ProtocolData storage _protocolState = getProtocolState(protocolId);

        return _protocolState.data;
    }
}
