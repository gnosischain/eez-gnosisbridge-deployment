// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title BlockRewardStub
/// @notice Stands in for the Gnosis Chain block reward contract on RollupX, where the native coin is minted by the
/// EEZ bridge and not by the xDAI bridge. It records what the xDAI bridge asked to mint and emits an event, but it
/// never transfers or mints any coin.
/// @dev Implements the IBlockReward interface used by HomeBridgeErcToNative. `mintedTotallyByBridge` is the cap the
/// home bridge applies to home-to-foreign transfers, so it must be recorded faithfully.
contract BlockRewardStub {
    /// @notice The home xDAI bridge proxy. The only address allowed to call `addExtraReceiver`.
    address public immutable bridge;

    uint256 public mintedTotally;
    mapping(address => uint256) public mintedTotallyByBridge;
    mapping(address => uint256) public mintedForAccount;

    event AddedReceiver(uint256 amount, address indexed receiver, address indexed bridge);

    constructor(address _bridge) {
        require(_bridge != address(0), "zero bridge");
        bridge = _bridge;
    }

    /// @notice Called by the home xDAI bridge when a foreign-to-home transfer is executed.
    /// Records the amount and emits the event. No coin is minted or sent.
    function addExtraReceiver(uint256 _amount, address _receiver) external {
        require(msg.sender == bridge, "not bridge");
        require(_amount != 0, "zero amount");
        mintedTotally += _amount;
        mintedTotallyByBridge[msg.sender] += _amount;
        mintedForAccount[_receiver] += _amount;
        emit AddedReceiver(_amount, _receiver, msg.sender);
    }

    function bridgesAllowedLength() external pure returns (uint256) {
        return 1;
    }

    function blockRewardContractId() external pure returns (bytes4) {
        return bytes4(keccak256("blockReward"));
    }

    /// @dev Fee distribution is not used (no fee manager is configured).
    function addBridgeTokenRewardReceivers(uint256) external pure {
        revert("not supported");
    }

    function addBridgeNativeRewardReceivers(uint256) external pure {
        revert("not supported");
    }
}
