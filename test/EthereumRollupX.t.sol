// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PairTest} from "./PairTest.sol";
import {PairConfig, Config} from "../script/lib/Config.sol";

/// @notice Ethereum (foreign) <-> RollupX (home). Needs ETHEREUM_RPC_URL and ROLLUPX_RPC_URL.
contract EthereumRollupXTest is PairTest {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function _config() internal pure override returns (PairConfig memory) {
        return Config.ethereumRollupX();
    }

    /// @dev Last blocks before the live deployment of 2026-11-24 (first deployment blocks: 26486214 and 1163461).
    function _freshForkBlocks() internal pure override returns (uint256, uint256) {
        return (26486213, 1163460);
    }

    /// @dev WETH is bridged as a plain ERC-20 (D6).
    function _omnibridgeToken() internal pure override returns (address) {
        return WETH;
    }
}
