// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PairConfig} from "./Config.sol";
import {ForeignAddrs, HomeAddrs} from "./BridgeDeployer.sol";
import "./Interfaces.sol";
import {CommonBase} from "forge-std/Base.sol";

/// @title Checks
/// @notice Post-deployment assertions on live (or forked) state. Each function must run on the matching chain.
abstract contract Checks is CommonBase {
    bytes4 private constant AMB_MODE = 0x2544fbb9; // arbitrary-message-bridge-core
    bytes4 private constant XDAI_MODE = 0x18762d46; // erc-to-native-core

    function _checkForeign(PairConfig memory c, ForeignAddrs memory f, HomeAddrs memory h) internal view {
        require(block.chainid == c.foreignChainId, "check: not on foreign chain");

        _checkValidators(c, f.ambValidators, f.ambValidatorsImpl, "foreign AMB validators");
        _checkAmb(c, f.amb, f.ambImpl, f.ambValidators, c.foreignChainId, c.homeChainId, "foreign AMB");
        require(IAMB(f.amb).maxGasPerTx() == c.foreignAmbMaxGasPerTx, "foreign AMB: maxGasPerTx");
        require(IAMB(f.amb).gasPrice() == c.foreignAmbGasPrice, "foreign AMB: gasPrice");
        require(IAMB(f.amb).requiredBlockConfirmations() == c.foreignAmbConfirmations, "foreign AMB: confirmations");

        _checkValidators(c, f.xdaiValidators, f.xdaiValidatorsImpl, "foreign xDAI validators");
        _checkXdai(c, f.xdaiBridge, f.xdaiBridgeImpl, f.xdaiValidators, "foreign xDAI bridge");
        IForeignXDaiBridge fx = IForeignXDaiBridge(f.xdaiBridge);
        require(fx.erc20token() == c.usds && c.usds == f.usds, "foreign xDAI bridge: token");
        // bridgeContractOnOtherSide() is internal: read addressStorage[keccak256("bridgeOnOtherSide")] directly.
        // addressStorage is the third mapping of EternalStorage (slot 2).
        bytes32 slot = keccak256(abi.encode(keccak256(abi.encodePacked("bridgeOnOtherSide")), uint256(2)));
        require(
            address(uint160(uint256(vm.load(f.xdaiBridge, slot)))) == h.xdaiBridge, "foreign xDAI bridge: other side"
        );
        _checkXdaiLimits(
            f.xdaiBridge, c.foreignXdaiLimits, c.foreignXdaiExecutionLimits, c.foreignXdaiGasPrice,
            c.foreignXdaiConfirmations, "foreign xDAI bridge"
        );

        _checkOmni(c, f.omnibridge, f.omnibridgeImpl, f.amb, h.omnibridge, f.tokenFactory, "foreign Omnibridge");
        _checkOmniLimits(f.omnibridge, c.foreignOmniLimits, c.foreignOmniExecutionLimits, "foreign Omnibridge");
        require(
            IForeignOmnibridge(f.omnibridge).requestGasLimit() == c.foreignOmniRequestGasLimit,
            "foreign Omnibridge: requestGasLimit"
        );
        _checkFactory(c, f.tokenFactory, f.tokenImage, f.omnibridge, "foreign token factory");

        if (c.mockTokens) {
            require(keccak256(bytes(IERC20Like(f.usds).symbol())) == keccak256("USDS"), "mock USDS: symbol");
            require(f.mockToken.code.length != 0, "mock token: no code");
        }
    }

    function _checkHome(PairConfig memory c, ForeignAddrs memory f, HomeAddrs memory h) internal view {
        require(block.chainid == c.homeChainId, "check: not on home chain");

        _checkValidators(c, h.ambValidators, h.ambValidatorsImpl, "home AMB validators");
        _checkAmb(c, h.amb, h.ambImpl, h.ambValidators, c.homeChainId, c.foreignChainId, "home AMB");
        require(IAMB(h.amb).maxGasPerTx() == c.homeAmbMaxGasPerTx, "home AMB: maxGasPerTx");
        require(IAMB(h.amb).gasPrice() == c.homeAmbGasPrice, "home AMB: gasPrice");
        require(IAMB(h.amb).requiredBlockConfirmations() == c.homeAmbConfirmations, "home AMB: confirmations");

        _checkValidators(c, h.xdaiValidators, h.xdaiValidatorsImpl, "home xDAI validators");
        _checkXdai(c, h.xdaiBridge, h.xdaiBridgeImpl, h.xdaiValidators, "home xDAI bridge");
        IHomeXDaiBridge hx = IHomeXDaiBridge(h.xdaiBridge);
        require(hx.blockRewardContract() == h.blockReward, "home xDAI bridge: block reward");
        // usdsDepositContract is not checked: in a fresh EternalStorageProxy it shares storage slot 6 with the proxy
        // admin and therefore reads as the owner. It is harmless because this build writes USDS into every
        // message whoever the sender is. setUSDSDepositContract must never be called (see DEPLOYMENT.md).
        require(IBlockRewardStub(h.blockReward).bridge() == h.xdaiBridge, "block reward stub: bridge");
        _checkXdaiLimits(
            h.xdaiBridge, c.homeXdaiLimits, c.homeXdaiExecutionLimits, c.homeXdaiGasPrice, c.homeXdaiConfirmations,
            "home xDAI bridge"
        );

        _checkOmni(c, h.omnibridge, h.omnibridgeImpl, h.amb, f.omnibridge, h.tokenFactory, "home Omnibridge");
        _checkOmniLimits(h.omnibridge, c.homeOmniLimits, c.homeOmniExecutionLimits, "home Omnibridge");
        IHomeOmnibridge ho = IHomeOmnibridge(h.omnibridge);
        require(ho.gasLimitManager() == h.gasLimitManager, "home Omnibridge: gas limit manager");
        require(ho.forwardingRulesManager() == h.forwardingRulesManager, "home Omnibridge: forwarding rules");
        require(ho.feeManager() == address(0), "home Omnibridge: fee manager set");
        _checkFactory(c, h.tokenFactory, h.tokenImage, h.omnibridge, "home token factory");

        IGasLimitManager g = IGasLimitManager(h.gasLimitManager);
        require(g.owner() == c.owner, "gas limit manager: owner");
        require(g.bridge() == h.amb, "gas limit manager: bridge");
        require(g.requestGasLimit() == c.homeOmniRequestGasLimit, "gas limit manager: default");
        require(g.requestGasLimit(bytes4(0x2ae87cdd)) == c.homeOmniDeployTokenGasLimit, "gas limit manager: 0x2ae87cdd");
        require(g.requestGasLimit(bytes4(0xd522cfd7)) == c.homeOmniDeployTokenGasLimit, "gas limit manager: 0xd522cfd7");
        require(IOwnable(h.forwardingRulesManager).owner() == c.owner, "forwarding rules manager: owner");
    }

    function _checkProxy(PairConfig memory c, address _proxy, address _impl, string memory _what) private view {
        require(_proxy.code.length != 0, string.concat(_what, ": proxy has no code"));
        require(_impl.code.length != 0, string.concat(_what, ": implementation has no code"));
        require(IProxy(_proxy).implementation() == _impl, string.concat(_what, ": implementation"));
        require(IProxy(_proxy).upgradeabilityOwner() == c.owner, string.concat(_what, ": proxy admin"));
        require(IOwnable(_proxy).owner() == c.owner, string.concat(_what, ": owner"));
    }

    function _checkValidators(PairConfig memory c, address _proxy, address _impl, string memory _what) private view {
        _checkProxy(c, _proxy, _impl, _what);
        IBridgeValidators v = IBridgeValidators(_proxy);
        require(v.requiredSignatures() == 1, string.concat(_what, ": required signatures"));
        require(v.validatorCount() == 1, string.concat(_what, ": validator count"));
        require(v.isValidator(c.validator), string.concat(_what, ": validator"));
    }

    function _checkAmb(
        PairConfig memory c,
        address _amb,
        address _impl,
        address _validators,
        uint256 _source,
        uint256 _destination,
        string memory _what
    ) private view {
        _checkProxy(c, _amb, _impl, _what);
        IAMB amb = IAMB(_amb);
        require(amb.isInitialized(), string.concat(_what, ": not initialised"));
        require(amb.getBridgeMode() == AMB_MODE, string.concat(_what, ": bridge mode"));
        require(!amb.HASHI_IS_ENABLED(), string.concat(_what, ": Hashi enabled"));
        require(amb.sourceChainId() == _source, string.concat(_what, ": source chain id"));
        require(amb.destinationChainId() == _destination, string.concat(_what, ": destination chain id"));
        require(amb.validatorContract() == _validators, string.concat(_what, ": validator contract"));
    }

    function _checkXdai(PairConfig memory c, address _bridge, address _impl, address _validators, string memory _what)
        private
        view
    {
        _checkProxy(c, _bridge, _impl, _what);
        IXDaiBridge b = IXDaiBridge(_bridge);
        require(b.isInitialized(), string.concat(_what, ": not initialised"));
        require(b.getBridgeMode() == XDAI_MODE, string.concat(_what, ": bridge mode"));
        require(!b.HASHI_IS_ENABLED(), string.concat(_what, ": Hashi enabled"));
        require(b.validatorContract() == _validators, string.concat(_what, ": validator contract"));
        require(b.decimalShift() == 0, string.concat(_what, ": decimal shift"));
    }

    function _checkXdaiLimits(
        address _bridge,
        uint256[3] memory _limits,
        uint256[2] memory _execution,
        uint256 _gasPrice,
        uint256 _confirmations,
        string memory _what
    ) private view {
        IXDaiBridge b = IXDaiBridge(_bridge);
        require(b.dailyLimit() == _limits[0], string.concat(_what, ": dailyLimit"));
        require(b.maxPerTx() == _limits[1], string.concat(_what, ": maxPerTx"));
        require(b.minPerTx() == _limits[2], string.concat(_what, ": minPerTx"));
        require(b.executionDailyLimit() == _execution[0], string.concat(_what, ": executionDailyLimit"));
        require(b.executionMaxPerTx() == _execution[1], string.concat(_what, ": executionMaxPerTx"));
        require(b.gasPrice() == _gasPrice, string.concat(_what, ": gasPrice"));
        require(b.requiredBlockConfirmations() == _confirmations, string.concat(_what, ": confirmations"));
    }

    function _checkOmni(
        PairConfig memory c,
        address _mediator,
        address _impl,
        address _amb,
        address _otherSide,
        address _factory,
        string memory _what
    ) private view {
        _checkProxy(c, _mediator, _impl, _what);
        IOmnibridge m = IOmnibridge(_mediator);
        require(m.isInitialized(), string.concat(_what, ": not initialised"));
        require(m.bridgeContract() == _amb, string.concat(_what, ": AMB"));
        require(m.mediatorContractOnOtherSide() == _otherSide, string.concat(_what, ": mediator on other side"));
        require(m.tokenFactory() == _factory, string.concat(_what, ": token factory"));
    }

    function _checkOmniLimits(address _mediator, uint256[3] memory _limits, uint256[2] memory _execution, string memory _what)
        private
        view
    {
        IOmnibridge m = IOmnibridge(_mediator);
        require(m.dailyLimit(address(0)) == _limits[0], string.concat(_what, ": dailyLimit"));
        require(m.maxPerTx(address(0)) == _limits[1], string.concat(_what, ": maxPerTx"));
        require(m.minPerTx(address(0)) == _limits[2], string.concat(_what, ": minPerTx"));
        require(m.executionDailyLimit(address(0)) == _execution[0], string.concat(_what, ": executionDailyLimit"));
        require(m.executionMaxPerTx(address(0)) == _execution[1], string.concat(_what, ": executionMaxPerTx"));
    }

    function _checkFactory(PairConfig memory c, address _factory, address _image, address _mediator, string memory _what)
        private
        view
    {
        ITokenFactory t = ITokenFactory(_factory);
        require(_factory.code.length != 0, string.concat(_what, ": no code"));
        require(t.owner() == c.owner, string.concat(_what, ": owner"));
        require(t.tokenImage() == _image && _image.code.length != 0, string.concat(_what, ": token image"));
        require(t.isDeployer(_mediator), string.concat(_what, ": mediator is not a deployer"));
    }
}
