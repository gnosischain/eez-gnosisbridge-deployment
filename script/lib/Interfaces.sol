// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Minimal interfaces of the legacy bridge contracts (solc 0.4.24 / 0.7.5), which are loaded as prebuilt artifacts.

interface IProxy {
    function upgradeTo(uint256 version, address implementation) external;
    function transferProxyOwnership(address newOwner) external;
    function upgradeabilityOwner() external view returns (address);
    function implementation() external view returns (address);
    function version() external view returns (uint256);
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IBridgeValidators is IOwnable {
    function initialize(uint256 requiredSignatures, address[] calldata initialValidators, address owner)
        external
        returns (bool);
    function requiredSignatures() external view returns (uint256);
    function validatorCount() external view returns (uint256);
    function isValidator(address validator) external view returns (bool);
    function addValidator(address validator) external;
}

interface IAMB is IOwnable {
    function initialize(
        uint256 sourceChainId,
        uint256 destinationChainId,
        address validatorContract,
        uint256 maxGasPerTx,
        uint256 gasPrice,
        uint256 requiredBlockConfirmations,
        address owner
    ) external returns (bool);
    function isInitialized() external view returns (bool);
    function getBridgeMode() external view returns (bytes4);
    function HASHI_IS_ENABLED() external view returns (bool);
    function sourceChainId() external view returns (uint256);
    function destinationChainId() external view returns (uint256);
    function validatorContract() external view returns (address);
    function maxGasPerTx() external view returns (uint256);
    function gasPrice() external view returns (uint256);
    function requiredBlockConfirmations() external view returns (uint256);
    function requireToPassMessage(address target, bytes calldata data, uint256 gas) external returns (bytes32);
    function messageSender() external view returns (address);
    function messageCallStatus(bytes32 messageId) external view returns (bool);
    // home
    function executeAffirmation(bytes calldata message) external;
    // foreign
    function executeSignatures(bytes calldata data, bytes calldata signatures) external;
}

interface IXDaiBridge is IOwnable {
    function isInitialized() external view returns (bool);
    function getBridgeMode() external view returns (bytes4);
    function HASHI_IS_ENABLED() external view returns (bool);
    function validatorContract() external view returns (address);
    function dailyLimit() external view returns (uint256);
    function maxPerTx() external view returns (uint256);
    function minPerTx() external view returns (uint256);
    function executionDailyLimit() external view returns (uint256);
    function executionMaxPerTx() external view returns (uint256);
    function gasPrice() external view returns (uint256);
    function requiredBlockConfirmations() external view returns (uint256);
    function decimalShift() external view returns (int256);
}

interface IHomeXDaiBridge is IXDaiBridge {
    function initialize(
        address validatorContract,
        uint256[3] calldata dailyLimitMaxPerTxMinPerTx,
        uint256 homeGasPrice,
        uint256 requiredBlockConfirmations,
        address blockReward,
        uint256[2] calldata foreignDailyLimitForeignMaxPerTx,
        address owner,
        int256 decimalShift
    ) external returns (bool);
    function blockRewardContract() external view returns (address);
    function totalBurntCoins() external view returns (uint256);
    function usdsDepositContract() external view returns (address);
    function relayTokens(address receiver) external payable;
    function executeAffirmation(address recipient, uint256 value, bytes32 nonce) external;
}

interface IForeignXDaiBridge is IXDaiBridge {
    function initialize(
        address validatorContract,
        address erc20token,
        uint256 requiredBlockConfirmations,
        uint256 gasPrice,
        uint256[3] calldata dailyLimitMaxPerTxMinPerTx,
        uint256[2] calldata homeDailyLimitHomeMaxPerTx,
        address owner,
        int256 decimalShift,
        address bridgeOnOtherSide
    ) external returns (bool);
    function erc20token() external view returns (address);
    function relayTokens(address receiver, uint256 amount) external;
    function executeSignatures(bytes calldata message, bytes calldata signatures) external;
}

interface IBlockRewardStub {
    function bridge() external view returns (address);
    function mintedTotally() external view returns (uint256);
    function mintedTotallyByBridge(address bridge) external view returns (uint256);
    function mintedForAccount(address account) external view returns (uint256);
}

interface ITokenFactory is IOwnable {
    function tokenImage() external view returns (address);
    function setTokenImage(address tokenImage) external;
    function setDeployer(address deployer, bool allowed) external;
    function isDeployer(address deployer) external view returns (bool);
    function predictTokenProxyAddress(address token) external view returns (address);
}

interface IGasLimitManager is IOwnable {
    function bridge() external view returns (address);
    function requestGasLimit() external view returns (uint256);
    function requestGasLimit(bytes4 selector) external view returns (uint256);
    function setRequestGasLimit(bytes4 selector, uint256 gasLimit) external;
}

interface IOmnibridge is IOwnable {
    function isInitialized() external view returns (bool);
    function bridgeContract() external view returns (address);
    function mediatorContractOnOtherSide() external view returns (address);
    function tokenFactory() external view returns (address);
    function dailyLimit(address token) external view returns (uint256);
    function maxPerTx(address token) external view returns (uint256);
    function minPerTx(address token) external view returns (uint256);
    function executionDailyLimit(address token) external view returns (uint256);
    function executionMaxPerTx(address token) external view returns (uint256);
    function bridgedTokenAddress(address nativeToken) external view returns (address);
    function nativeTokenAddress(address bridgedToken) external view returns (address);
    function bridgedTokenAddressOrPredicted(address nativeToken) external view returns (address);
    function mediatorBalance(address token) external view returns (uint256);
    function relayTokens(address token, address receiver, uint256 value) external;
}

interface IHomeOmnibridge is IOmnibridge {
    function initialize(
        address bridgeContract,
        address mediatorContract,
        uint256[3] calldata dailyLimitMaxPerTxMinPerTx,
        uint256[2] calldata executionDailyLimitExecutionMaxPerTx,
        address gasLimitManager,
        address owner,
        address tokenFactory,
        address feeManager,
        address forwardingRulesManager
    ) external returns (bool);
    function gasLimitManager() external view returns (address);
    function feeManager() external view returns (address);
    function forwardingRulesManager() external view returns (address);
}

interface IForeignOmnibridge is IOmnibridge {
    function initialize(
        address bridgeContract,
        address mediatorContract,
        uint256[3] calldata dailyLimitMaxPerTxMinPerTx,
        uint256[2] calldata executionDailyLimitExecutionMaxPerTx,
        uint256 requestGasLimit,
        address owner,
        address tokenFactory
    ) external returns (bool);
    function requestGasLimit() external view returns (uint256);
}

interface IERC20Like {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);
    function owner() external view returns (address);
}
