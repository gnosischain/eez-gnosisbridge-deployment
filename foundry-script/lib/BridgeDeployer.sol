// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {PairConfig, Config, Salts} from "./Config.sol";
import "./Interfaces.sol";
import {MockERC20} from "../../src/MockERC20.sol";
import {BlockRewardStub} from "../../src/BlockRewardStub.sol";

struct ForeignAddrs {
    address usds;
    address mockToken;
    address ambValidatorsImpl;
    address ambValidators;
    address ambImpl;
    address amb;
    address xdaiValidatorsImpl;
    address xdaiValidators;
    address xdaiBridgeImpl;
    address xdaiBridge;
    address tokenImage;
    address tokenFactory;
    address omnibridgeImpl;
    address omnibridge;
}

struct HomeAddrs {
    address ambValidatorsImpl;
    address ambValidators;
    address ambImpl;
    address amb;
    address xdaiValidatorsImpl;
    address xdaiValidators;
    address blockReward;
    address xdaiBridgeImpl;
    address xdaiBridge;
    address tokenImage;
    address tokenFactory;
    address gasLimitManager;
    address forwardingRulesManager;
    address omnibridgeImpl;
    address omnibridge;
}

/// @title BridgeDeployer
/// @notice Deployment steps shared by the broadcast scripts and the fork tests. Every function expects the caller
/// context (vm.startBroadcast or vm.startPrank) to be set already, with `_deployer` as the transaction sender.
///
/// A pair is deployed in three stages because both the xDAI bridge and the Omnibridge need the address of their
/// counterpart on the other chain at initialisation:
///   1. foreign: deploy everything, initialise what does not depend on the home chain
///   2. home:    deploy and initialise everything, hand all roles to the owner
///   3. foreign: initialise the xDAI bridge and the Omnibridge, hand all roles to the owner
/// Between stages 1 and 3 the foreign proxies are uninitialised but owned by the deployer; `initialize` can only be
/// called by the proxy owner, so they cannot be taken over.
abstract contract BridgeDeployer is CommonBase {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes4 internal constant DEPLOY_AND_HANDLE = 0x2ae87cdd; // deployAndHandleBridgedTokens(...)
    bytes4 internal constant DEPLOY_AND_HANDLE_AND_CALL = 0xd522cfd7; // deployAndHandleBridgedTokensAndCall(...)

    // ------------------------------------------------------------------------------------------------------------
    // Stage 1: foreign chain
    // ------------------------------------------------------------------------------------------------------------

    function _deployForeign(PairConfig memory c, address _deployer) internal returns (ForeignAddrs memory f) {
        require(block.chainid == c.foreignChainId, "wrong chain: expected foreign");

        if (c.mockTokens) {
            f.usds = _create2(Salts.MOCK_USDS, _mockInitCode("USDS", "USDS"));
            f.mockToken = _create2(Salts.MOCK_TOKEN, _mockInitCode("EEZ Bridge Test Token", "EBT"));
        } else {
            f.usds = c.usds;
        }
        require(f.usds == c.usds, "USDS address differs from config and patch");
        require(f.usds.code.length != 0, "USDS has no code");

        // AMB: complete on this side
        (f.ambValidatorsImpl, f.ambValidators) = _deployValidators("amb", c);
        f.ambImpl = _create(_artifact("amb", "ForeignAMB"));
        f.amb = _proxy("amb", f.ambImpl);
        IAMB(f.amb).initialize(
            c.foreignChainId,
            c.homeChainId,
            f.ambValidators,
            c.foreignAmbMaxGasPerTx,
            c.foreignAmbGasPrice,
            c.foreignAmbConfirmations,
            c.owner
        );
        IProxy(f.amb).transferProxyOwnership(c.owner);

        // xDAI bridge: proxy is initialised in stage 3
        (f.xdaiValidatorsImpl, f.xdaiValidators) = _deployValidators(c.xdaiTree, c);
        f.xdaiBridgeImpl = _create(_artifact(c.xdaiTree, "XDaiForeignBridge"));
        f.xdaiBridge = _proxy(c.xdaiTree, f.xdaiBridgeImpl);

        // Omnibridge: proxy is initialised in stage 3
        f.tokenImage = _deployTokenImage();
        f.omnibridge = _create(_artifact("omnibridge", "EternalStorageProxy"));
        f.tokenFactory = _deployTokenFactory(Salts.FOREIGN_TOKEN_FACTORY, _deployer, f.tokenImage, f.omnibridge, c.owner);
        f.omnibridgeImpl =
            _create(abi.encodePacked(_artifact("omnibridge", "ForeignOmnibridge"), abi.encode(c.foreignTokenSuffix)));
        IProxy(f.omnibridge).upgradeTo(1, f.omnibridgeImpl);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Stage 2: home chain
    // ------------------------------------------------------------------------------------------------------------

    function _deployHome(PairConfig memory c, address _deployer, ForeignAddrs memory f)
        internal
        returns (HomeAddrs memory h)
    {
        require(block.chainid == c.homeChainId, "wrong chain: expected home");
        require(f.omnibridge != address(0) && f.xdaiBridge != address(0), "foreign stage 1 missing");

        // AMB
        (h.ambValidatorsImpl, h.ambValidators) = _deployValidators("amb", c);
        h.ambImpl = _create(_artifact("amb", "HomeAMB"));
        h.amb = _proxy("amb", h.ambImpl);
        IAMB(h.amb).initialize(
            c.homeChainId,
            c.foreignChainId,
            h.ambValidators,
            c.homeAmbMaxGasPerTx,
            c.homeAmbGasPrice,
            c.homeAmbConfirmations,
            c.owner
        );
        IProxy(h.amb).transferProxyOwnership(c.owner);

        _deployHomeXdai(c, h);
        _deployHomeOmnibridge(c, _deployer, f, h);
    }

    function _deployHomeXdai(PairConfig memory c, HomeAddrs memory h) private {
        (h.xdaiValidatorsImpl, h.xdaiValidators) = _deployValidators(c.xdaiTree, c);
        h.xdaiBridgeImpl = _create(_artifact(c.xdaiTree, "HomeBridgeErcToNative"));
        h.xdaiBridge = _proxy(c.xdaiTree, h.xdaiBridgeImpl);
        // The stub only accepts calls from the bridge proxy, so the proxy has to exist first.
        h.blockReward = address(new BlockRewardStub(h.xdaiBridge));
        IHomeXDaiBridge(h.xdaiBridge).initialize(
            h.xdaiValidators,
            c.homeXdaiLimits,
            c.homeXdaiGasPrice,
            c.homeXdaiConfirmations,
            h.blockReward,
            c.homeXdaiExecutionLimits,
            c.owner,
            0
        );
        IProxy(h.xdaiBridge).transferProxyOwnership(c.owner);
    }

    function _deployHomeOmnibridge(PairConfig memory c, address _deployer, ForeignAddrs memory f, HomeAddrs memory h)
        private
    {
        h.tokenImage = _deployTokenImage();
        h.omnibridge = _create(_artifact("omnibridge", "EternalStorageProxy"));
        h.tokenFactory = _deployTokenFactory(Salts.HOME_TOKEN_FACTORY, _deployer, h.tokenImage, h.omnibridge, c.owner);

        // Owned by the deployer until the selector limits are set, then handed to the owner.
        h.gasLimitManager = _create(
            abi.encodePacked(
                _artifact("omnibridge", "SelectorTokenGasLimitManager"),
                abi.encode(h.amb, _deployer, c.homeOmniRequestGasLimit)
            )
        );
        IGasLimitManager(h.gasLimitManager).setRequestGasLimit(DEPLOY_AND_HANDLE, c.homeOmniDeployTokenGasLimit);
        IGasLimitManager(h.gasLimitManager).setRequestGasLimit(
            DEPLOY_AND_HANDLE_AND_CALL, c.homeOmniDeployTokenGasLimit
        );
        IOwnable(h.gasLimitManager).transferOwnership(c.owner);

        h.forwardingRulesManager = _create(
            abi.encodePacked(_artifact("omnibridge", "MultiTokenForwardingRulesManager"), abi.encode(c.owner))
        );

        h.omnibridgeImpl =
            _create(abi.encodePacked(_artifact("omnibridge", "HomeOmnibridge"), abi.encode(c.homeTokenSuffix)));
        IProxy(h.omnibridge).upgradeTo(1, h.omnibridgeImpl);
        IHomeOmnibridge(h.omnibridge).initialize(
            h.amb,
            f.omnibridge,
            c.homeOmniLimits,
            c.homeOmniExecutionLimits,
            h.gasLimitManager,
            c.owner,
            h.tokenFactory,
            address(0), // no fee manager: bridge fees are disabled
            h.forwardingRulesManager
        );
        IProxy(h.omnibridge).transferProxyOwnership(c.owner);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Stage 3: foreign chain
    // ------------------------------------------------------------------------------------------------------------

    function _finalizeForeign(PairConfig memory c, ForeignAddrs memory f, HomeAddrs memory h) internal {
        require(block.chainid == c.foreignChainId, "wrong chain: expected foreign");
        require(h.omnibridge != address(0) && h.xdaiBridge != address(0), "home stage missing");

        IForeignXDaiBridge(f.xdaiBridge).initialize(
            f.xdaiValidators,
            f.usds,
            c.foreignXdaiConfirmations,
            c.foreignXdaiGasPrice,
            c.foreignXdaiLimits,
            c.foreignXdaiExecutionLimits,
            c.owner,
            0,
            h.xdaiBridge
        );
        IProxy(f.xdaiBridge).transferProxyOwnership(c.owner);

        IForeignOmnibridge(f.omnibridge).initialize(
            f.amb,
            h.omnibridge,
            c.foreignOmniLimits,
            c.foreignOmniExecutionLimits,
            c.foreignOmniRequestGasLimit,
            c.owner,
            f.tokenFactory
        );
        IProxy(f.omnibridge).transferProxyOwnership(c.owner);
    }

    // ------------------------------------------------------------------------------------------------------------
    // Building blocks
    // ------------------------------------------------------------------------------------------------------------

    function _deployValidators(string memory _tree, PairConfig memory c)
        private
        returns (address impl, address proxy)
    {
        impl = _create(_artifact(_tree, "BridgeValidators"));
        proxy = _proxy(_tree, impl);
        address[] memory validators = new address[](1);
        validators[0] = c.validator;
        IBridgeValidators(proxy).initialize(1, validators, c.owner);
        IProxy(proxy).transferProxyOwnership(c.owner);
    }

    /// @dev PermittableToken image from the Omnibridge precompiled (solc 0.4.24) artifact.
    function _deployTokenImage() private returns (address) {
        string memory json = vm.readFile("build/omnibridge/precompiled/PermittableToken.json");
        return _create(
            abi.encodePacked(vm.parseJsonBytes(json, ".bytecode"), abi.encode("", "", uint8(0), block.chainid))
        );
    }

    /// @dev TokenFactory through the CREATE2 deployer (EIP-7997), as required by Omnibridge PR 6. Created with
    /// (owner = deployer, image = 0) so the address depends only on the deployer and the salt.
    function _deployTokenFactory(bytes32 _salt, address _deployer, address _image, address _mediator, address _owner)
        private
        returns (address factory)
    {
        factory =
            _create2(_salt, abi.encodePacked(_artifact("omnibridge", "TokenFactory"), abi.encode(_deployer, address(0))));
        ITokenFactory(factory).setTokenImage(_image);
        ITokenFactory(factory).setDeployer(_mediator, true);
        ITokenFactory(factory).transferOwnership(_owner);
    }

    function _proxy(string memory _tree, address _impl) private returns (address proxy) {
        proxy = _create(_artifact(_tree, "EternalStorageProxy"));
        IProxy(proxy).upgradeTo(1, _impl);
    }

    function _mockInitCode(string memory _name, string memory _symbol) internal pure returns (bytes memory) {
        return abi.encodePacked(type(MockERC20).creationCode, abi.encode(_name, _symbol, uint8(18)));
    }

    function _artifact(string memory _tree, string memory _name) internal view returns (bytes memory code) {
        code = vm.getCode(string.concat("build/", _tree, "/out/", _name, ".sol/", _name, ".json"));
        require(code.length != 0, string.concat("missing artifact: ", _tree, "/", _name));
    }

    function _create(bytes memory _code) internal returns (address a) {
        assembly {
            a := create(0, add(_code, 0x20), mload(_code))
        }
        require(a != address(0) && a.code.length != 0, "create failed");
    }

    function _create2Address(bytes32 _salt, bytes memory _initCode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, _salt, keccak256(_initCode)))))
        );
    }

    function _create2(bytes32 _salt, bytes memory _initCode) internal returns (address a) {
        require(CREATE2_DEPLOYER.code.length != 0, "CREATE2 deployer missing");
        a = _create2Address(_salt, _initCode);
        require(a.code.length == 0, "CREATE2 target already deployed");
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(_salt, _initCode));
        require(ok && a.code.length != 0, "create2 failed");
    }

    // ------------------------------------------------------------------------------------------------------------
    // Address book: deployments/<pair>/{foreign,home}.json
    // ------------------------------------------------------------------------------------------------------------

    function _path(PairConfig memory c, string memory _side) internal pure returns (string memory) {
        return string.concat("deployments/", c.name, "/", _side, ".json");
    }

    function _writeForeign(PairConfig memory c, ForeignAddrs memory f) internal {
        string memory o = "foreign";
        vm.serializeUint(o, "chainId", c.foreignChainId);
        vm.serializeAddress(o, "usds", f.usds);
        vm.serializeAddress(o, "mockToken", f.mockToken);
        vm.serializeAddress(o, "ambValidatorsImpl", f.ambValidatorsImpl);
        vm.serializeAddress(o, "ambValidators", f.ambValidators);
        vm.serializeAddress(o, "ambImpl", f.ambImpl);
        vm.serializeAddress(o, "amb", f.amb);
        vm.serializeAddress(o, "xdaiValidatorsImpl", f.xdaiValidatorsImpl);
        vm.serializeAddress(o, "xdaiValidators", f.xdaiValidators);
        vm.serializeAddress(o, "xdaiBridgeImpl", f.xdaiBridgeImpl);
        vm.serializeAddress(o, "xdaiBridge", f.xdaiBridge);
        vm.serializeAddress(o, "tokenImage", f.tokenImage);
        vm.serializeAddress(o, "tokenFactory", f.tokenFactory);
        vm.serializeAddress(o, "omnibridgeImpl", f.omnibridgeImpl);
        vm.writeJson(vm.serializeAddress(o, "omnibridge", f.omnibridge), _path(c, "foreign"));
    }

    function _readForeign(PairConfig memory c) internal view returns (ForeignAddrs memory f) {
        string memory j = vm.readFile(_path(c, "foreign"));
        require(vm.parseJsonUint(j, ".chainId") == c.foreignChainId, "foreign.json: wrong chain");
        f.usds = vm.parseJsonAddress(j, ".usds");
        f.mockToken = vm.parseJsonAddress(j, ".mockToken");
        f.ambValidatorsImpl = vm.parseJsonAddress(j, ".ambValidatorsImpl");
        f.ambValidators = vm.parseJsonAddress(j, ".ambValidators");
        f.ambImpl = vm.parseJsonAddress(j, ".ambImpl");
        f.amb = vm.parseJsonAddress(j, ".amb");
        f.xdaiValidatorsImpl = vm.parseJsonAddress(j, ".xdaiValidatorsImpl");
        f.xdaiValidators = vm.parseJsonAddress(j, ".xdaiValidators");
        f.xdaiBridgeImpl = vm.parseJsonAddress(j, ".xdaiBridgeImpl");
        f.xdaiBridge = vm.parseJsonAddress(j, ".xdaiBridge");
        f.tokenImage = vm.parseJsonAddress(j, ".tokenImage");
        f.tokenFactory = vm.parseJsonAddress(j, ".tokenFactory");
        f.omnibridgeImpl = vm.parseJsonAddress(j, ".omnibridgeImpl");
        f.omnibridge = vm.parseJsonAddress(j, ".omnibridge");
    }

    function _writeHome(PairConfig memory c, HomeAddrs memory h) internal {
        string memory o = "home";
        vm.serializeUint(o, "chainId", c.homeChainId);
        vm.serializeAddress(o, "ambValidatorsImpl", h.ambValidatorsImpl);
        vm.serializeAddress(o, "ambValidators", h.ambValidators);
        vm.serializeAddress(o, "ambImpl", h.ambImpl);
        vm.serializeAddress(o, "amb", h.amb);
        vm.serializeAddress(o, "xdaiValidatorsImpl", h.xdaiValidatorsImpl);
        vm.serializeAddress(o, "xdaiValidators", h.xdaiValidators);
        vm.serializeAddress(o, "blockReward", h.blockReward);
        vm.serializeAddress(o, "xdaiBridgeImpl", h.xdaiBridgeImpl);
        vm.serializeAddress(o, "xdaiBridge", h.xdaiBridge);
        vm.serializeAddress(o, "tokenImage", h.tokenImage);
        vm.serializeAddress(o, "tokenFactory", h.tokenFactory);
        vm.serializeAddress(o, "gasLimitManager", h.gasLimitManager);
        vm.serializeAddress(o, "forwardingRulesManager", h.forwardingRulesManager);
        vm.serializeAddress(o, "omnibridgeImpl", h.omnibridgeImpl);
        vm.writeJson(vm.serializeAddress(o, "omnibridge", h.omnibridge), _path(c, "home"));
    }

    function _readHome(PairConfig memory c) internal view returns (HomeAddrs memory h) {
        string memory j = vm.readFile(_path(c, "home"));
        require(vm.parseJsonUint(j, ".chainId") == c.homeChainId, "home.json: wrong chain");
        h.ambValidatorsImpl = vm.parseJsonAddress(j, ".ambValidatorsImpl");
        h.ambValidators = vm.parseJsonAddress(j, ".ambValidators");
        h.ambImpl = vm.parseJsonAddress(j, ".ambImpl");
        h.amb = vm.parseJsonAddress(j, ".amb");
        h.xdaiValidatorsImpl = vm.parseJsonAddress(j, ".xdaiValidatorsImpl");
        h.xdaiValidators = vm.parseJsonAddress(j, ".xdaiValidators");
        h.blockReward = vm.parseJsonAddress(j, ".blockReward");
        h.xdaiBridgeImpl = vm.parseJsonAddress(j, ".xdaiBridgeImpl");
        h.xdaiBridge = vm.parseJsonAddress(j, ".xdaiBridge");
        h.tokenImage = vm.parseJsonAddress(j, ".tokenImage");
        h.tokenFactory = vm.parseJsonAddress(j, ".tokenFactory");
        h.gasLimitManager = vm.parseJsonAddress(j, ".gasLimitManager");
        h.forwardingRulesManager = vm.parseJsonAddress(j, ".forwardingRulesManager");
        h.omnibridgeImpl = vm.parseJsonAddress(j, ".omnibridgeImpl");
        h.omnibridge = vm.parseJsonAddress(j, ".omnibridge");
    }
}
