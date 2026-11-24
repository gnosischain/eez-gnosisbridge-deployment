// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @dev Parameters of one bridge pair. Home is the RollupX side, foreign is the L1 side.
struct PairConfig {
    string name; // file name stem under deployments/
    string xdaiTree; // build/<xdaiTree>: xDAI bridge build carrying this pair's token constants
    string homeRpc; // alias in foundry.toml [rpc_endpoints]
    string foreignRpc;
    uint256 homeChainId;
    uint256 foreignChainId;
    address owner; // receives every owner and proxy-admin role
    address validator; // sole validator, required signatures = 1
    bool mockTokens; // true: deploy mock USDS and a mock ERC-20 on the foreign chain
    address usds; // token locked by the foreign xDAI bridge
    // AMB
    uint256 homeAmbMaxGasPerTx;
    uint256 homeAmbGasPrice;
    uint256 homeAmbConfirmations;
    uint256 foreignAmbMaxGasPerTx;
    uint256 foreignAmbGasPrice;
    uint256 foreignAmbConfirmations;
    // xDAI bridge: [daily, maxPerTx, minPerTx] and [executionDaily, executionMaxPerTx]
    uint256[3] homeXdaiLimits;
    uint256[2] homeXdaiExecutionLimits;
    uint256 homeXdaiGasPrice;
    uint256 homeXdaiConfirmations;
    uint256[3] foreignXdaiLimits;
    uint256[2] foreignXdaiExecutionLimits;
    uint256 foreignXdaiGasPrice;
    uint256 foreignXdaiConfirmations;
    // Omnibridge
    uint256[3] homeOmniLimits;
    uint256[2] homeOmniExecutionLimits;
    uint256 homeOmniRequestGasLimit;
    uint256 homeOmniDeployTokenGasLimit;
    string homeTokenSuffix;
    uint256[3] foreignOmniLimits;
    uint256[2] foreignOmniExecutionLimits;
    uint256 foreignOmniRequestGasLimit;
    string foreignTokenSuffix;
}

/// @dev Bridge parameters are the production Ethereum <-> Gnosis Chain values, read from the live contracts on
/// 2026-11-23 (foreign side from Ethereum, home side from Gnosis Chain). See DEPLOYMENT.md for the source addresses.
library Config {
    address internal constant OWNER = 0xB4265633387DAe42a822c5DaF2f90C8d799C9455;
    address internal constant VALIDATOR = 0xC18516Ce413cB899bC3f8bBA4c204bF97BE990E6;

    /// @dev Mock USDS on Chiado: MockERC20("USDS", "USDS", 18) created through the CREATE2 deployer with
    /// Salts.MOCK_USDS. The same address is written into patches/xdai-chiado-mock-usds.patch.
    address internal constant CHIADO_MOCK_USDS = 0xB691934cfF2030235195Db7b905d3Db9779fBFF6;
    address internal constant ETHEREUM_USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    function byName(string memory _name) internal pure returns (PairConfig memory) {
        bytes32 h = keccak256(bytes(_name));
        if (h == keccak256("chiado-rollupx-testnet")) return chiadoRollupXTestnet();
        if (h == keccak256("ethereum-rollupx")) return ethereumRollupX();
        revert("unknown pair");
    }

    function chiadoRollupXTestnet() internal pure returns (PairConfig memory c) {
        c = _production();
        c.name = "chiado-rollupx-testnet";
        c.xdaiTree = "xdai-testnet";
        c.homeRpc = "rollupx_testnet";
        c.foreignRpc = "chiado";
        c.homeChainId = 699169;
        c.foreignChainId = 10200;
        c.mockTokens = true;
        c.usds = CHIADO_MOCK_USDS;
        c.homeTokenSuffix = " on RollupX Testnet";
        c.foreignTokenSuffix = " on Chiado";
    }

    function ethereumRollupX() internal pure returns (PairConfig memory c) {
        c = _production();
        c.name = "ethereum-rollupx";
        c.xdaiTree = "xdai-mainnet";
        c.homeRpc = "rollupx";
        c.foreignRpc = "ethereum";
        c.homeChainId = 696991;
        c.foreignChainId = 1;
        c.mockTokens = false;
        c.usds = ETHEREUM_USDS;
        c.homeTokenSuffix = " on RollupX";
        // Home-to-foreign xDAI minimum: 1 wei instead of the production 10 coins, which would be 10 ETH here.
        c.homeXdaiLimits[2] = 1;
        c.foreignTokenSuffix = " on Ethereum";
    }

    function _production() private pure returns (PairConfig memory c) {
        c.owner = OWNER;
        c.validator = VALIDATOR;

        // AMB
        c.homeAmbMaxGasPerTx = 2_000_000;
        c.homeAmbGasPrice = 0;
        c.homeAmbConfirmations = 100;
        c.foreignAmbMaxGasPerTx = 4_000_000;
        c.foreignAmbGasPrice = 10 gwei;
        c.foreignAmbConfirmations = 175;

        // xDAI bridge
        c.homeXdaiLimits = [uint256(10_000_000 ether + 1), 10_000_000 ether, 10 ether];
        c.homeXdaiExecutionLimits = [uint256(15_000_000 ether), 9_999_999 ether];
        c.homeXdaiGasPrice = 0;
        c.homeXdaiConfirmations = 20;
        c.foreignXdaiLimits = [uint256(10_000_000 ether), 9_999_999 ether, 0.005 ether];
        c.foreignXdaiExecutionLimits = [uint256(15_000_000 ether), 10_000_000 ether];
        c.foreignXdaiGasPrice = 100 gwei;
        c.foreignXdaiConfirmations = 20;

        // Omnibridge
        c.homeOmniLimits = [uint256(1e37 + 10), 1e36, 1 ether];
        c.homeOmniExecutionLimits = [uint256(1e37 + 10), 1e36];
        c.homeOmniRequestGasLimit = 600_000;
        // Omnibridge PR 6: CREATE2 token deployment needs more gas than the production default.
        c.homeOmniDeployTokenGasLimit = 850_000;
        c.foreignOmniLimits = [uint256(1e37 + 10), 1e36, 1];
        c.foreignOmniExecutionLimits = [uint256(1e37 + 10), 1e36];
        c.foreignOmniRequestGasLimit = 2_000_000;
    }
}

library Salts {
    bytes32 internal constant MOCK_USDS = keccak256("eez-gnosisbridge-deploy/MockUSDS/v1");
    bytes32 internal constant MOCK_TOKEN = keccak256("eez-gnosisbridge-deploy/MockToken/v1");
    bytes32 internal constant HOME_TOKEN_FACTORY = keccak256("eez-gnosisbridge-deploy/TokenFactory/home/v1");
    bytes32 internal constant FOREIGN_TOKEN_FACTORY = keccak256("eez-gnosisbridge-deploy/TokenFactory/foreign/v1");
}
