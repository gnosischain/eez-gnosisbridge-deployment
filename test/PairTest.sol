// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {PairConfig} from "../script/lib/Config.sol";
import {BridgeDeployer, ForeignAddrs, HomeAddrs} from "../script/lib/BridgeDeployer.sol";
import {Checks} from "../script/lib/Checks.sol";
import "../script/lib/Interfaces.sol";

contract AMBReceiver {
    uint256 public value;
    address public caller;
    address public messageSender;

    function ping(uint256 _value) external {
        value = _value;
        caller = msg.sender;
        messageSender = IAMB(msg.sender).messageSender();
    }
}

/// @title PairTest
/// @notice Contract-level cross-chain tests on two forks. A "relay" is done by reading the event on the source
/// fork and calling the destination bridge directly, so no oracle and no block finality are involved.
///
/// By default the pair is deployed on the forks with the same code as the broadcast scripts, on chain state from
/// just before the live deployment. With USE_DEPLOYED=true the tests attach to the live addresses in
/// deployments/<pair>/ on the latest blocks.
///
/// Home-to-foreign relays need a real ECDSA signature. The key of the mock validator is not known to the tests, so
/// a test validator is added by the owner (pranked) on the foreign validator contracts.
abstract contract PairTest is Test, BridgeDeployer, Checks {
    // AMB
    event UserRequestForAffirmation(bytes32 indexed messageId, bytes encodedData);
    event UserRequestForSignature(bytes32 indexed messageId, bytes encodedData);
    event AffirmationCompleted(address indexed sender, address indexed executor, bytes32 indexed messageId, bool status);
    event RelayedMessage(address indexed sender, address indexed executor, bytes32 indexed messageId, bool status);
    // Omnibridge
    event TokensBridgingInitiated(address indexed token, address indexed sender, uint256 value, bytes32 indexed messageId);
    event TokensBridged(address indexed token, address indexed recipient, uint256 value, bytes32 indexed messageId);
    event NewTokenRegistered(address indexed nativeToken, address indexed bridgedToken);
    // xDAI bridge (same names as the AMB events, different parameters)
    event AffirmationCompleted(address recipient, uint256 value, bytes32 nonce);
    event RelayedMessage(address recipient, uint256 value, bytes32 transactionHash);
    event AddedReceiver(uint256 amount, address indexed receiver, address indexed bridge);

    bytes32 internal constant T_AMB_AFFIRMATION = keccak256("UserRequestForAffirmation(bytes32,bytes)");
    bytes32 internal constant T_AMB_SIGNATURE = keccak256("UserRequestForSignature(bytes32,bytes)");
    bytes32 internal constant T_AMB_AFFIRMATION_COMPLETED = keccak256("AffirmationCompleted(address,address,bytes32,bool)");
    bytes32 internal constant T_AMB_RELAYED = keccak256("RelayedMessage(address,address,bytes32,bool)");
    bytes32 internal constant T_OMNI_INITIATED = keccak256("TokensBridgingInitiated(address,address,uint256,bytes32)");
    bytes32 internal constant T_OMNI_BRIDGED = keccak256("TokensBridged(address,address,uint256,bytes32)");
    bytes32 internal constant T_OMNI_REGISTERED = keccak256("NewTokenRegistered(address,address)");
    bytes32 internal constant T_XDAI_AFFIRMATION = keccak256("UserRequestForAffirmation(address,uint256,bytes32)");
    bytes32 internal constant T_XDAI_SIGNATURE = keccak256("UserRequestForSignature(address,uint256,bytes32,address)");

    PairConfig internal c;
    ForeignAddrs internal f;
    HomeAddrs internal h;
    uint256 internal foreignFork;
    uint256 internal homeFork;

    address internal user;
    address internal receiver;
    address internal testValidator;
    uint256 internal testValidatorKey;

    function _config() internal pure virtual returns (PairConfig memory);

    /// @dev Fork blocks for the fresh-deployment mode: (foreign, home), 0 for the latest block.
    function _freshForkBlocks() internal pure virtual returns (uint256, uint256);

    /// @dev Token used for the Omnibridge tests on the foreign chain.
    function _omnibridgeToken() internal view virtual returns (address);

    function setUp() public virtual {
        c = _config();
        if (vm.envOr("USE_DEPLOYED", false)) {
            foreignFork = vm.createFork(vm.rpcUrl(c.foreignRpc));
            homeFork = vm.createFork(vm.rpcUrl(c.homeRpc));
            f = _readForeign(c);
            h = _readHome(c);
        } else {
            // A fresh deployment needs chain state from before the live one, otherwise the CREATE2 contracts
            // already exist. _freshForkBlocks() returns the last blocks before the live deployment (0 = latest).
            (uint256 foreignBlock, uint256 homeBlock) = _freshForkBlocks();
            foreignFork = foreignBlock == 0
                ? vm.createFork(vm.rpcUrl(c.foreignRpc))
                : vm.createFork(vm.rpcUrl(c.foreignRpc), foreignBlock);
            homeFork =
                homeBlock == 0 ? vm.createFork(vm.rpcUrl(c.homeRpc)) : vm.createFork(vm.rpcUrl(c.homeRpc), homeBlock);

            address deployer = vm.envOr("DEPLOYER", address(0x652987962C5cb6660755a8432AA2526DD7a89366));
            vm.selectFork(foreignFork);
            vm.startPrank(deployer);
            f = _deployForeign(c, deployer);
            vm.stopPrank();

            vm.selectFork(homeFork);
            vm.startPrank(deployer);
            h = _deployHome(c, deployer, f);
            vm.stopPrank();

            vm.selectFork(foreignFork);
            vm.startPrank(deployer);
            _finalizeForeign(c, f, h);
            vm.stopPrank();
        }

        // The deployment must pass the same checks as the live one, before the tests touch the validator set.
        vm.selectFork(foreignFork);
        _checkForeign(c, f, h);
        vm.selectFork(homeFork);
        _checkHome(c, f, h);

        user = makeAddr("user");
        receiver = makeAddr("receiver");
        (testValidator, testValidatorKey) = makeAddrAndKey("testValidator");

        vm.selectFork(foreignFork);
        vm.startPrank(c.owner);
        IBridgeValidators(f.ambValidators).addValidator(testValidator);
        IBridgeValidators(f.xdaiValidators).addValidator(testValidator);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------------------------------------------
    // AMB
    // ------------------------------------------------------------------------------------------------------------

    function test_AMB_ForeignToHome() public {
        vm.selectFork(homeFork);
        AMBReceiver target = new AMBReceiver();

        vm.selectFork(foreignFork);
        vm.recordLogs();
        vm.prank(user);
        bytes32 messageId = IAMB(f.amb).requireToPassMessage(address(target), abi.encodeCall(AMBReceiver.ping, (42)), 200_000);
        Vm.Log memory request = _findLog(vm.getRecordedLogs(), f.amb, T_AMB_AFFIRMATION);
        assertEq(request.topics[1], messageId, "source event: messageId");
        bytes memory message = abi.decode(request.data, (bytes));

        vm.selectFork(homeFork);
        vm.expectEmit(true, true, true, true, h.amb);
        emit AffirmationCompleted(user, address(target), messageId, true);
        vm.prank(c.validator);
        IAMB(h.amb).executeAffirmation(message);

        assertEq(target.value(), 42);
        assertEq(target.caller(), h.amb);
        assertEq(target.messageSender(), user);
        assertTrue(IAMB(h.amb).messageCallStatus(messageId));
    }

    function test_AMB_HomeToForeign() public {
        vm.selectFork(foreignFork);
        AMBReceiver target = new AMBReceiver();

        vm.selectFork(homeFork);
        vm.recordLogs();
        vm.prank(user);
        bytes32 messageId = IAMB(h.amb).requireToPassMessage(address(target), abi.encodeCall(AMBReceiver.ping, (7)), 200_000);
        Vm.Log memory request = _findLog(vm.getRecordedLogs(), h.amb, T_AMB_SIGNATURE);
        assertEq(request.topics[1], messageId, "source event: messageId");
        bytes memory message = abi.decode(request.data, (bytes));

        vm.selectFork(foreignFork);
        vm.expectEmit(true, true, true, true, f.amb);
        emit RelayedMessage(user, address(target), messageId, true);
        IAMB(f.amb).executeSignatures(message, _sign(message));

        assertEq(target.value(), 7);
        assertEq(target.messageSender(), user);
        assertTrue(IAMB(f.amb).messageCallStatus(messageId));
    }

    function test_AMB_RevertWhen_NotValidator() public {
        vm.selectFork(foreignFork);
        vm.recordLogs();
        vm.prank(user);
        IAMB(f.amb).requireToPassMessage(address(0xBEEF), hex"00", 100_000);
        bytes memory message = abi.decode(_findLog(vm.getRecordedLogs(), f.amb, T_AMB_AFFIRMATION).data, (bytes));

        vm.selectFork(homeFork);
        vm.prank(user);
        vm.expectRevert();
        IAMB(h.amb).executeAffirmation(message);
    }

    function test_AMB_RevertWhen_SignedByNonValidator() public {
        vm.selectFork(homeFork);
        vm.recordLogs();
        vm.prank(user);
        IAMB(h.amb).requireToPassMessage(address(0xBEEF), hex"00", 100_000);
        bytes memory message = abi.decode(_findLog(vm.getRecordedLogs(), h.amb, T_AMB_SIGNATURE).data, (bytes));

        (, uint256 strangerKey) = makeAddrAndKey("stranger");
        bytes memory signatures = _signWith(strangerKey, message);
        vm.selectFork(foreignFork);
        vm.expectRevert();
        IAMB(f.amb).executeSignatures(message, signatures);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Omnibridge
    // ------------------------------------------------------------------------------------------------------------

    function test_Omnibridge_ForeignToHome() public {
        _omnibridgeForeignToHome(100 ether);
    }

    function test_Omnibridge_ForeignToHome_SecondTransferDoesNotRedeploy() public {
        address bridged = _omnibridgeForeignToHome(100 ether);

        (bytes32 messageId, bytes memory message) = _omnibridgeRelayFromForeign(5 ether);
        vm.selectFork(homeFork);
        vm.recordLogs();
        vm.prank(c.validator);
        IAMB(h.amb).executeAffirmation(message);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(_hasLog(logs, h.omnibridge, T_OMNI_REGISTERED), "token registered twice");
        assertTrue(IAMB(h.amb).messageCallStatus(messageId));
        assertEq(IOmnibridge(h.omnibridge).bridgedTokenAddress(_omnibridgeToken()), bridged);
        assertEq(IERC20Like(bridged).balanceOf(receiver), 105 ether);
    }

    function test_Omnibridge_HomeToForeign() public {
        address token = _omnibridgeToken();
        address bridged = _omnibridgeForeignToHome(100 ether);
        uint256 amount = 40 ether;

        // source: home. The bridged token is burnt.
        vm.selectFork(homeFork);
        uint256 supplyBefore = IERC20Like(bridged).totalSupply();
        vm.recordLogs();
        vm.prank(receiver);
        IERC20Like(bridged).transferAndCall(h.omnibridge, amount, abi.encodePacked(user));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(IERC20Like(bridged).balanceOf(receiver), 60 ether, "source balance not decreased");
        assertEq(IERC20Like(bridged).totalSupply(), supplyBefore - amount, "bridged token not burnt");
        Vm.Log memory initiated = _findLog(logs, h.omnibridge, T_OMNI_INITIATED);
        assertEq(address(uint160(uint256(initiated.topics[1]))), bridged);
        assertEq(address(uint160(uint256(initiated.topics[2]))), receiver);
        assertEq(abi.decode(initiated.data, (uint256)), amount);
        Vm.Log memory request = _findLog(logs, h.amb, T_AMB_SIGNATURE);
        bytes32 messageId = request.topics[1];
        assertEq(initiated.topics[3], messageId);
        bytes memory message = abi.decode(request.data, (bytes));

        // destination: foreign. The locked native token is released.
        vm.selectFork(foreignFork);
        uint256 userBefore = IERC20Like(token).balanceOf(user);
        uint256 mediatorBefore = IERC20Like(token).balanceOf(f.omnibridge);
        vm.expectEmit(true, true, true, true, f.omnibridge);
        emit TokensBridged(token, user, amount, messageId);
        vm.expectEmit(true, true, true, true, f.amb);
        emit RelayedMessage(h.omnibridge, f.omnibridge, messageId, true);
        IAMB(f.amb).executeSignatures(message, _sign(message));

        assertEq(IERC20Like(token).balanceOf(user), userBefore + amount);
        assertEq(IERC20Like(token).balanceOf(f.omnibridge), mediatorBefore - amount);
    }

    function test_Omnibridge_RevertWhen_BelowMinPerTx() public {
        address token = _omnibridgeToken();
        vm.selectFork(foreignFork);
        _fund(token, user, 1 ether);
        vm.startPrank(user);
        IERC20Like(token).approve(f.omnibridge, 1 ether);
        vm.expectRevert();
        IOmnibridge(f.omnibridge).relayTokens(token, receiver, 0);
        vm.stopPrank();
    }

    /// @dev Bridges `_amount` from `user` on foreign to `receiver` on home and returns the bridged token.
    function _omnibridgeForeignToHome(uint256 _amount) internal returns (address bridged) {
        address token = _omnibridgeToken();
        vm.selectFork(foreignFork);
        address predicted = address(0);
        bool firstTime;

        (bytes32 messageId, bytes memory message) = _omnibridgeRelayFromForeign(_amount);

        vm.selectFork(homeFork);
        firstTime = IOmnibridge(h.omnibridge).bridgedTokenAddress(token) == address(0);
        predicted = IOmnibridge(h.omnibridge).bridgedTokenAddressOrPredicted(token);
        assertEq(predicted, ITokenFactory(h.tokenFactory).predictTokenProxyAddress(token), "prediction mismatch");

        vm.recordLogs();
        vm.prank(c.validator);
        IAMB(h.amb).executeAffirmation(message);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bridged = IOmnibridge(h.omnibridge).bridgedTokenAddress(token);
        assertEq(bridged, predicted, "bridged token is not at the predicted CREATE2 address");
        assertGt(bridged.code.length, 0);
        assertEq(IOmnibridge(h.omnibridge).nativeTokenAddress(bridged), token);

        if (firstTime) {
            Vm.Log memory registered = _findLog(logs, h.omnibridge, T_OMNI_REGISTERED);
            assertEq(address(uint160(uint256(registered.topics[1]))), token);
            assertEq(address(uint160(uint256(registered.topics[2]))), bridged);
        }
        Vm.Log memory done = _findLog(logs, h.omnibridge, T_OMNI_BRIDGED);
        assertEq(address(uint160(uint256(done.topics[1]))), bridged);
        assertEq(address(uint160(uint256(done.topics[2]))), receiver);
        assertEq(abi.decode(done.data, (uint256)), _amount);
        assertEq(done.topics[3], messageId);
        Vm.Log memory completed = _findLog(logs, h.amb, T_AMB_AFFIRMATION_COMPLETED);
        assertEq(completed.topics[3], messageId);
        assertTrue(abi.decode(completed.data, (bool)), "AMB message execution failed");

        assertEq(IERC20Like(bridged).balanceOf(receiver), _amount);
        assertEq(IERC20Like(bridged).decimals(), 18);
        vm.selectFork(foreignFork);
        string memory expectedName = string.concat(IERC20Like(token).name(), c.homeTokenSuffix);
        vm.selectFork(homeFork);
        assertEq(IERC20Like(bridged).name(), expectedName);
        assertEq(IERC20Like(bridged).owner(), h.omnibridge);
    }

    /// @dev Source half of a foreign-to-home Omnibridge transfer: user -> receiver.
    function _omnibridgeRelayFromForeign(uint256 _amount) internal returns (bytes32 messageId, bytes memory message) {
        address token = _omnibridgeToken();
        vm.selectFork(foreignFork);
        _fund(token, user, _amount);
        uint256 userBefore = IERC20Like(token).balanceOf(user);
        uint256 mediatorBefore = IERC20Like(token).balanceOf(f.omnibridge);

        vm.startPrank(user);
        IERC20Like(token).approve(f.omnibridge, _amount);
        vm.recordLogs();
        IOmnibridge(f.omnibridge).relayTokens(token, receiver, _amount);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(IERC20Like(token).balanceOf(user), userBefore - _amount, "source balance not decreased");
        assertEq(IERC20Like(token).balanceOf(f.omnibridge), mediatorBefore + _amount, "tokens not locked");

        Vm.Log memory initiated = _findLog(logs, f.omnibridge, T_OMNI_INITIATED);
        assertEq(address(uint160(uint256(initiated.topics[1]))), token);
        assertEq(address(uint160(uint256(initiated.topics[2]))), user);
        assertEq(abi.decode(initiated.data, (uint256)), _amount);
        Vm.Log memory request = _findLog(logs, f.amb, T_AMB_AFFIRMATION);
        messageId = request.topics[1];
        assertEq(initiated.topics[3], messageId);
        message = abi.decode(request.data, (bytes));
    }

    // ------------------------------------------------------------------------------------------------------------
    // xDAI bridge
    // ------------------------------------------------------------------------------------------------------------

    function test_XDai_ForeignToHome_EmitsEventsAndMintsNothing() public {
        _xdaiForeignToHome(100 ether);
    }

    function test_XDai_HomeToForeign_RelayTokens() public {
        _xdaiForeignToHome(100 ether);
        _xdaiHomeToForeign(20 ether, false);
    }

    function test_XDai_HomeToForeign_PlainTransfer() public {
        _xdaiForeignToHome(100 ether);
        _xdaiHomeToForeign(20 ether, true);
    }

    /// @dev `usdsDepositContract` shares a storage slot with the proxy admin, so the owner is treated as the USDS
    /// deposit contract. The message must carry this pair's USDS for the owner like for anyone else.
    function test_XDai_HomeToForeign_OwnerAsSenderStillCarriesUsds() public {
        _xdaiForeignToHome(100 ether);
        vm.selectFork(homeFork);
        assertEq(IHomeXDaiBridge(h.xdaiBridge).usdsDepositContract(), IProxy(h.xdaiBridge).upgradeabilityOwner());
        vm.deal(c.owner, 20 ether);
        vm.recordLogs();
        vm.prank(c.owner);
        IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: 20 ether}(receiver);
        Vm.Log memory request = _findLog(vm.getRecordedLogs(), h.xdaiBridge, T_XDAI_SIGNATURE);
        (,,, address token) = abi.decode(request.data, (address, uint256, bytes32, address));
        assertEq(token, c.usds, "message does not carry USDS");
    }

    function test_XDai_HomeToForeign_RevertWhen_NothingWasDeposited() public {
        vm.selectFork(homeFork);
        uint256 recorded = IBlockRewardStub(h.blockReward).mintedTotallyByBridge(h.xdaiBridge);
        uint256 burnt = IHomeXDaiBridge(h.xdaiBridge).totalBurntCoins();
        uint256 amount = recorded - burnt + c.homeXdaiLimits[2];
        vm.deal(user, amount);
        vm.prank(user);
        vm.expectRevert();
        IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: amount}(receiver);
    }

    function test_XDai_HomeToForeign_RevertWhen_AboveRecordedDeposits() public {
        _xdaiForeignToHome(30 ether);
        vm.selectFork(homeFork);
        uint256 headroom = IBlockRewardStub(h.blockReward).mintedTotallyByBridge(h.xdaiBridge)
            - IHomeXDaiBridge(h.xdaiBridge).totalBurntCoins();
        vm.deal(user, headroom + 1 ether);
        vm.startPrank(user);
        vm.expectRevert();
        IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: headroom + 1}(receiver);
        // exactly the headroom is accepted
        IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: headroom}(receiver);
        vm.stopPrank();
    }

    function test_XDai_HomeToForeign_RevertWhen_BelowMinPerTx() public {
        _xdaiForeignToHome(100 ether);
        vm.selectFork(homeFork);
        vm.deal(user, 100 ether);
        vm.prank(user);
        vm.expectRevert();
        IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: c.homeXdaiLimits[2] - 1}(receiver);
    }

    function test_XDai_HomeToForeign_RevertWhen_PlainTransferHasCalldata() public {
        _xdaiForeignToHome(100 ether);
        vm.selectFork(homeFork);
        vm.deal(user, 100 ether);
        vm.prank(user);
        (bool ok,) = h.xdaiBridge.call{value: 20 ether}(hex"deadbeef");
        assertFalse(ok);
    }

    function test_XDai_ForeignToHome_RevertWhen_NotValidator() public {
        vm.selectFork(homeFork);
        vm.prank(user);
        vm.expectRevert();
        IHomeXDaiBridge(h.xdaiBridge).executeAffirmation(user, 1 ether, bytes32(uint256(1)));
    }

    function test_XDai_BlockRewardStub_OnlyBridge() public {
        vm.selectFork(homeFork);
        vm.prank(user);
        vm.expectRevert("not bridge");
        // forge-lint: disable-next-line(unsafe-typecast)
        (bool ok,) = h.blockReward.call(abi.encodeWithSignature("addExtraReceiver(uint256,address)", 1 ether, user));
        ok;
    }

    /// @dev user (foreign, USDS) -> receiver (home). Asserts that nothing is minted on home.
    function _xdaiForeignToHome(uint256 _amount) internal {
        vm.selectFork(foreignFork);
        _fund(f.usds, user, _amount);
        uint256 userBefore = IERC20Like(f.usds).balanceOf(user);
        uint256 bridgeBefore = IERC20Like(f.usds).balanceOf(f.xdaiBridge);

        vm.startPrank(user);
        IERC20Like(f.usds).approve(f.xdaiBridge, _amount);
        vm.recordLogs();
        IForeignXDaiBridge(f.xdaiBridge).relayTokens(receiver, _amount);
        vm.stopPrank();
        Vm.Log memory request = _findLog(vm.getRecordedLogs(), f.xdaiBridge, T_XDAI_AFFIRMATION);
        (address recipient, uint256 value, bytes32 nonce) = abi.decode(request.data, (address, uint256, bytes32));
        assertEq(recipient, receiver);
        assertEq(value, _amount);

        assertEq(IERC20Like(f.usds).balanceOf(user), userBefore - _amount, "source balance not decreased");
        assertEq(IERC20Like(f.usds).balanceOf(f.xdaiBridge), bridgeBefore + _amount, "USDS not locked");

        vm.selectFork(homeFork);
        uint256 nativeBefore = receiver.balance;
        uint256 recordedBefore = IBlockRewardStub(h.blockReward).mintedTotallyByBridge(h.xdaiBridge);

        vm.expectEmit(true, true, true, true, h.blockReward);
        emit AddedReceiver(_amount, receiver, h.xdaiBridge);
        vm.expectEmit(true, true, true, true, h.xdaiBridge);
        emit AffirmationCompleted(receiver, _amount, nonce);
        vm.prank(c.validator);
        IHomeXDaiBridge(h.xdaiBridge).executeAffirmation(recipient, value, nonce);

        assertEq(receiver.balance, nativeBefore, "native coin was minted or sent");
        assertEq(IBlockRewardStub(h.blockReward).mintedTotallyByBridge(h.xdaiBridge), recordedBefore + _amount);
        assertEq(h.blockReward.balance, 0);
    }

    /// @dev user (home, native coin) -> foreign USDS. With _plain the coin is sent with empty calldata and the
    /// recipient is the sender; otherwise relayTokens(receiver) is used.
    function _xdaiHomeToForeign(uint256 _amount, bool _plain) internal {
        vm.selectFork(homeFork);
        vm.deal(user, _amount);
        uint256 burntBefore = IHomeXDaiBridge(h.xdaiBridge).totalBurntCoins();
        uint256 zeroBefore = address(0).balance;
        address expectedRecipient = _plain ? user : receiver;

        vm.recordLogs();
        vm.prank(user);
        if (_plain) {
            (bool ok,) = h.xdaiBridge.call{value: _amount}("");
            assertTrue(ok, "plain transfer reverted");
        } else {
            IHomeXDaiBridge(h.xdaiBridge).relayTokens{value: _amount}(receiver);
        }
        Vm.Log memory request = _findLog(vm.getRecordedLogs(), h.xdaiBridge, T_XDAI_SIGNATURE);
        (address recipient, uint256 value, bytes32 nonce, address token) =
            abi.decode(request.data, (address, uint256, bytes32, address));

        assertEq(user.balance, 0, "source balance not decreased");
        assertEq(h.xdaiBridge.balance, 0, "coin left in the bridge");
        assertEq(address(0).balance, zeroBefore + _amount, "coin not burnt");
        assertEq(IHomeXDaiBridge(h.xdaiBridge).totalBurntCoins(), burntBefore + _amount);
        assertEq(recipient, expectedRecipient);
        assertEq(value, _amount);
        assertEq(token, c.usds, "message does not carry USDS");

        // The oracle builds this 124-byte message from the event; the validators sign it.
        bytes memory message = abi.encodePacked(recipient, value, nonce, f.xdaiBridge, token);
        assertEq(message.length, 124);

        vm.selectFork(foreignFork);
        uint256 recipientBefore = IERC20Like(f.usds).balanceOf(expectedRecipient);
        uint256 bridgeBefore = IERC20Like(f.usds).balanceOf(f.xdaiBridge);
        vm.expectEmit(true, true, true, true, f.xdaiBridge);
        emit RelayedMessage(expectedRecipient, _amount, nonce);
        IForeignXDaiBridge(f.xdaiBridge).executeSignatures(message, _sign(message));

        assertEq(IERC20Like(f.usds).balanceOf(expectedRecipient), recipientBefore + _amount, "USDS not received");
        assertEq(IERC20Like(f.usds).balanceOf(f.xdaiBridge), bridgeBefore - _amount);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------------------------------------------

    function _fund(address _token, address _to, uint256 _amount) internal {
        if (c.mockTokens) {
            IERC20Like(_token).mint(_to, _amount);
        } else {
            deal(_token, _to, IERC20Like(_token).balanceOf(_to) + _amount);
        }
    }

    /// @dev Signature blob accepted by executeSignatures: count, v, r, s. Works for AMB messages (any length) and
    /// for the 124-byte xDAI bridge messages: both hash the decimal message length into the prefix.
    function _sign(bytes memory _message) internal view returns (bytes memory) {
        return _signWith(testValidatorKey, _message);
    }

    function _signWith(uint256 _key, bytes memory _message) internal pure returns (bytes memory) {
        bytes32 hash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", vm.toString(_message.length), _message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_key, hash);
        return abi.encodePacked(uint8(1), v, r, s);
    }

    function _findLog(Vm.Log[] memory _logs, address _emitter, bytes32 _topic0) internal pure returns (Vm.Log memory) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter == _emitter && _logs[i].topics.length != 0 && _logs[i].topics[0] == _topic0) {
                return _logs[i];
            }
        }
        revert("expected event not found");
    }

    function _hasLog(Vm.Log[] memory _logs, address _emitter, bytes32 _topic0) internal pure returns (bool) {
        for (uint256 i = 0; i < _logs.length; i++) {
            if (_logs[i].emitter == _emitter && _logs[i].topics.length != 0 && _logs[i].topics[0] == _topic0) {
                return true;
            }
        }
        return false;
    }
}
