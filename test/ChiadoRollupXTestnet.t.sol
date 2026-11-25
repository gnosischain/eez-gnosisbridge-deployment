// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PairTest} from "./PairTest.sol";
import {PairConfig, Config} from "../foundry-script/lib/Config.sol";

/// @notice Chiado (foreign) <-> RollupX testnet (home). Needs CHIADO_RPC_URL and ROLLUPX_TESTNET_RPC_URL.
contract ChiadoRollupXTestnetTest is PairTest {
    function _config() internal pure override returns (PairConfig memory) {
        return Config.chiadoRollupXTestnet();
    }

    /// @dev Last blocks before the live deployment of 2026-11-23 (first deployment blocks: 24142212 and 2272511).
    function _freshForkBlocks() internal pure override returns (uint256, uint256) {
        return (24142211, 2272510);
    }

    function _omnibridgeToken() internal view override returns (address) {
        return f.mockToken;
    }
}
