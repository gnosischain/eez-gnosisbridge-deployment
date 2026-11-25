// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {PairConfig, Config} from "./lib/Config.sol";
import {BridgeDeployer, ForeignAddrs, HomeAddrs} from "./lib/BridgeDeployer.sol";
import {Checks} from "./lib/Checks.sol";

/// @title Deploy
/// @notice Deploys AMB + xDAI bridge + Omnibridge for one pair, selected with the PAIR environment variable
/// ("chiado-rollupx-testnet" or "ethereum-rollupx"). Run the stages in order; see the Makefile.
///
///   forge script foundry-script/Deploy.s.sol --sig "foreign()"  --broadcast --slow   # stage 1, foreign chain
///   forge script foundry-script/Deploy.s.sol --sig "home()"     --broadcast --slow   # stage 2, home chain
///   forge script foundry-script/Deploy.s.sol --sig "finalize()" --broadcast --slow   # stage 3, foreign chain
///   forge script foundry-script/Deploy.s.sol --sig "check()"                         # read-only, both chains
contract Deploy is Script, BridgeDeployer, Checks {
    function foreign() external {
        PairConfig memory c = _config();
        require(!vm.exists(_path(c, "foreign")), "foreign.json exists: stage 1 was already run");
        vm.createSelectFork(vm.rpcUrl(c.foreignRpc));

        vm.startBroadcast();
        ForeignAddrs memory f = _deployForeign(c, _broadcaster());
        vm.stopBroadcast();

        if (_broadcasting()) {
            vm.createDir(string.concat("deployments/", c.name), true);
            _writeForeign(c, f);
            console2.log("Stage 1 (foreign) address book:", _path(c, "foreign"));
        } else {
            console2.log("Stage 1 (foreign) simulated only, nothing written.");
        }
    }

    function home() external {
        PairConfig memory c = _config();
        require(!vm.exists(_path(c, "home")), "home.json exists: stage 2 was already run");
        ForeignAddrs memory f = _readForeign(c);
        vm.createSelectFork(vm.rpcUrl(c.homeRpc));

        vm.startBroadcast();
        HomeAddrs memory h = _deployHome(c, _broadcaster(), f);
        vm.stopBroadcast();

        _checkHome(c, f, h);
        if (_broadcasting()) {
            _writeHome(c, h);
            console2.log("Stage 2 (home) address book:", _path(c, "home"));
        } else {
            console2.log("Stage 2 (home) simulated only, nothing written.");
        }
    }

    function finalize() external {
        PairConfig memory c = _config();
        ForeignAddrs memory f = _readForeign(c);
        HomeAddrs memory h = _readHome(c);
        vm.createSelectFork(vm.rpcUrl(c.foreignRpc));

        vm.startBroadcast();
        _finalizeForeign(c, f, h);
        vm.stopBroadcast();

        _checkForeign(c, f, h);
        console2.log("Stage 3 (foreign) done: checks passed on the simulated state.");
    }

    /// @notice Read-only check of the live deployment on both chains.
    function check() external {
        PairConfig memory c = _config();
        ForeignAddrs memory f = _readForeign(c);
        HomeAddrs memory h = _readHome(c);

        vm.createSelectFork(vm.rpcUrl(c.foreignRpc));
        _checkForeign(c, f, h);
        console2.log("foreign chain OK:", c.foreignChainId);

        vm.createSelectFork(vm.rpcUrl(c.homeRpc));
        _checkHome(c, f, h);
        console2.log("home chain OK:", c.homeChainId);
    }

    function _config() private view returns (PairConfig memory) {
        return Config.byName(vm.envString("PAIR"));
    }

    /// @dev The address book is only written when the transactions are really sent (--broadcast or --resume),
    /// so a dry run never leaves addresses of contracts that do not exist.
    function _broadcasting() private view returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume);
    }

    function _broadcaster() private view returns (address sender) {
        (, sender,) = vm.readCallers();
    }
}
