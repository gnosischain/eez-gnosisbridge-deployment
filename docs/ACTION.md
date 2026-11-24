# ACTION.md — AMB + Omnibridge + xDAI bridge on RollupX

Breakdown of `INSTRUCTION.md` into concrete actions, based on research done on 2026-11-23.
Research was read-only: RPC probes, reading the three source branches, the EEZ repos and the Gnosis docs.
Nothing has been compiled, deployed or funded yet. Items marked **(unverified)** come from reading code, not from running it.
Decisions D1–D10 were settled by the user on 2026-11-23 and are recorded in section 2; the phases below have been updated to match.

Secrets (deployer private key, Blockscout API key) stay in `INSTRUCTION.md` / a git-ignored `.env`. They are not repeated here and must not be committed.

---

## 1. What the research established

### 1.1 Networks

| | Pair 1 (testnet) | Pair 2 |
|---|---|---|
| Foreign chain | Chiado, chain ID 10200 | Ethereum, chain ID 1 |
| Home chain | RollupX testnet, chain ID **699169** | RollupX, chain ID **696991** |
| Foreign RPC | `https://rpc.chiadochain.net` | the Tenderly URL in `INSTRUCTION.md` |
| Home RPC | `https://eez.dev/composer/l2` (plain node: `https://eez.dev/rpc/l2`) | `https://rollupx.eez.dev/composer/l2` (plain node: `https://rollupx.eez.dev/rpc/l2`) |
| Home explorer (Blockscout v9.0.2) | `https://eez.dev/explorer/` — API `https://eez.dev/explorer/api` | `https://rollupx.eez.dev/explorer/` — API `https://rollupx.eez.dev/explorer/api` |
| Home native gas token | bridged Chiado xDAI | bridged mainnet ETH |
| EEZ bridge (same address on L1 and L2) | `0xe993715bE7a0F60d484C5D19c4f008Ba79df1D4E` | `0x95273bf880ae09fdeb8c71d5aa37a0ba70835b55` |

- **The "Composer RPC URL" in `INSTRUCTION.md` (`…/composer/l1`) is the L1, not the rollup.** `eez.dev/composer/l1` returns chain ID 10200 and `rollupx.eez.dev/composer/l1` returns chain ID 1. The rollup RPC is `…/composer/l2`.
- The composer is a proxy that forwards ordinary `eth_*` transactions unchanged and composes EEZ cross-chain ones. Non-`eth_` methods are rejected, so use `/rpc/l2` when a tool needs `web3_clientVersion` or similar.
- Both rollups are stock reth with all forks through Osaka active. The per-transaction gas cap is 16,777,216 and the block gas limit is 30,000,000. Gas price is about 49 wei.
- L2 blocks can be rolled back if the L1 submission fails, so deployment scripts should wait for receipts and re-check code at each address before continuing.
- The CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` is present on all four chains.
- Multicall3, CreateX and the Safe singleton factory are absent on both rollups.

### 1.2 Accounts

| Role | Address | State |
|---|---|---|
| Deployer | `0x652987962C5cb6660755a8432AA2526DD7a89366` | **Balance 0 and nonce 0 on all four chains** |
| Owner | `0xB4265633387DAe42a822c5DaF2f90C8d799C9455` | receives all ownership and proxy-admin roles |
| Mock validator | `0xC18516Ce413cB899bC3f8bBA4c204bF97BE990E6` | sole validator, required signatures = 1 |

### 1.3 Source code

| Component | Source | Commit | Compiler | Foundry today |
|---|---|---|---|---|
| Omnibridge | `gnosischain/omnibridge` PR 6, branch `feat/create2-tokendeploy` | `65ee7afb` | 0.7.5 (token image is a precompiled 0.4.24 artifact) | full: scripts and a two-fork e2e harness |
| xDAI bridge | `gnosischain/tokenbridge-contracts` branch `xdaibridge` | `52afd25b` | 0.4.24 and 0.8.25 | partial: fork tests, no bridge deploy script |
| AMB | `gnosischain/tokenbridge-contracts` branch `master` | `47873407` | 0.4.24 | none (Truffle only) |

### 1.4 Problems found in the code (all unverified until compiled and tested)

1. **AMB on `master` cannot send messages as deployed by its own scripts.** Hashi is switched on by a constant, every `requireToPassMessage` calls `hashiManager().yaho().dispatchMessage(...)`, and no deploy script sets a Hashi manager. With none set the send should revert. Receiving is unaffected.
2. **The home xDAI bridge reverts on `executeAffirmation` without a block-reward contract.** It requires a non-zero `blockReward` and calls `addExtraReceiver` on it. With `address(0)` no event is emitted at all.
3. **`XDaiForeignBridge` hardcodes mainnet USDS, DAI, sUSDS, sDAI and the DAI-USDS converter.** It cannot be initialised with a mock token on Chiado. The home bridge and `Message.sol` also hardcode mainnet DAI/USDS as the token written into home-to-foreign messages.
4. **PR 6's all-in-one deploy script does not use the CREATE2 deployer for `TokenFactory`.** Only `script/DeployTokenFactory.s.sol` does, and it has to be run separately and passed in as `HOME_TOKEN_FACTORY`.
5. **PR 6 hardcodes the mainnet `WETHOmnibridgeRouter` address** `0xa6439Ca0FCbA1d0F80df0bE6A17220feD9c9038a` in `ForeignOmnibridge`. A newly deployed router at another address gets the non-reverting callback path.
6. **The JS deploy scripts on `master` and for the xDAI bridge send legacy transactions without a chain ID.** Use Foundry scripts instead of the JS path.
7. **`master` and `xdaibridge` share contract names with different code**, so they need separate build trees.
8. **Hashi is also switched on in the `xdaibridge` branch.** `BasicBridge.sol` has `HASHI_IS_ENABLED = true`, and both `relayTokens` paths (foreign and home) end in `_dispatchMessageWithHashi`, which calls the Hashi manager. With none set, xDAI bridge requests should revert in both directions. Resolved by O1.
9. **Home-to-foreign xDAI messages carry DAI by default.** The home bridge writes its `DAI` constant into the message unless the caller is the owner-set `usdsDepositContract`. Unmodified `XDaiForeignBridge` then converts USDS to DAI and pays the recipient DAI.

---

## 2. Decisions (settled 2026-11-23)

| # | Topic | Decision | Effect on the work |
|---|---|---|---|
| D1 | How to make the `master` AMB able to send (problem 1) | **Set `HASHI_IS_ENABLED` to `false`.** | One-line patch to `contracts/upgradeable_contracts/BasicBridge.sol` in the `master` tree, committed as a `.patch` file. No `HashiManager`, no Yaho stub, no `setHashiManager` call. The AMB is verified from patched source, so it will not match upstream bytecode. |
| D2 | Home xDAI "event only, no mint" (problem 2) | **Deploy a small `BlockRewardStub` that transfers nothing.** | Stub implements `IBlockReward`, records `mintedTotallyByBridge`, emits `AddedReceiver`, sends no coin. |
| D3 | Foreign xDAI bridge on Chiado (problem 3) | **Patch the token constant in the bridge contract to the newly deployed mock USDS.** | Chiado runs `XDaiForeignBridge` (not the generic `ForeignBridgeErcToNative`) built from patched source. See the patch notes below the table. |
| D4 | Foreign xDAI bridge on Ethereum | **Agreed.** | Deploy `XDaiForeignBridge` with real USDS, no `initializeInterest`, no `BridgeRouter`. The only change from upstream is the Hashi constant (O1). |
| D5 | Home-to-foreign xDAI on RollupX | **Allow transferring native coin to the home xDAI bridge and emit the event as usual. The cap is negligible.** | Direction is in scope and tested on both pairs. Both entry points are covered: `relayTokens(receiver)` and a plain transfer to the bridge. See O2 for how the cap is handled. |
| D6 | WETH on Ethereum (problem 5) | **Agreed.** | WETH is bridged as a plain ERC-20. No `WETHOmnibridgeRouter`. |
| D7 | `TokenFactory` via CREATE2 | **Agreed.** | CREATE2 through `0x4e59…956C` on both sides, distinct salt per mediator. |
| D8 | Bridge parameters | **All follow the mainnet parameters, except token name suffixes, which use the chain name.** | Limits, `maxGasPerTx`, confirmations and gas price values are read from the live production contracts and written into both config files. See O3. |
| D9 | Deployer key shared in plaintext | **Accepted: the deployment is for testing only.** | Same key for both pairs, no fresh key. Roles are still handed to the Owner and checked, because the instruction requires it. |
| D10 | Ethereum verification target | **Blockscout only.** | Ethereum contracts are verified on `eth.blockscout.com`. No Etherscan. |

### D3 patch notes (unverified)

- Mock USDS is deployed first through the CREATE2 deployer with a fixed salt, so its address is known before compiling and the patch is a static committed diff.
- Foreign side, Chiado build only: replace the mainnet USDS literal in `XDaiForeignBridge.sol` (`USDS` constant) and in `SavingsDaiConnector.sol` (`daiToken()` and the inline literals). `initialize` requires `_erc20token == daiToken()`, so both files must agree.
- Home side, testnet build only: point the home bridge's `DAI` constant at the mock USDS, so messages carry the mock USDS and the foreign bridge takes its plain-transfer branch.
- The foreign `DAI` and `DAI_USDS` constants must **not** be set to the mock USDS: the DAI branch is checked first and calls the DAI-USDS converter, which does not exist on Chiado.
- The sUSDS address stays untouched; it is only reached if interest is initialised or the bridge balance is short, neither of which happens here.

### Points arising from the decisions (all settled 2026-11-23)

| # | Point | Outcome |
|---|---|---|
| O1 | Hashi in the `xdaibridge` tree (problem 8). | **Confirmed by the user on 2026-11-23:** apply the same `HASHI_IS_ENABLED = false` patch to the `xdaibridge` tree for both pairs. The request events are still emitted; only the Hashi dispatch is skipped. The Ethereum `XDaiForeignBridge` differs from upstream by that one constant. |
| O2 | Reading of "the cap is negligible" in D5. | **Confirmed by the user on 2026-11-23:** the cap stays as the contract implements it. A home-to-foreign transfer only works after a foreign-to-home transfer has been executed on the home chain (`executeAffirmation`), which raises the stub's `mintedTotallyByBridge`. Transfers are accepted up to total recorded deposits minus total burnt; before any deposit they revert. |
| O3 | Reading of D8. | **Confirmed by the user on 2026-11-23:** "mainnet parameters" means the production Ethereum ↔ Gnosis Chain values, used for **both** pairs: foreign-side values from the Ethereum contracts, home-side values from the Gnosis Chain contracts. Validators stay as the single mock validator with threshold 1. Omnibridge token name suffixes: ` on RollupX` / ` on RollupX Testnet` for tokens created on the home side, ` on Ethereum` / ` on Chiado` for tokens created on the foreign side. |
| O4 | Payout token for home-to-foreign (problem 9). User preference 2026-11-23: USDS only, no DAI logic, no USDS deposit contract. | Patch the home bridge's `DAI` constant to that pair's USDS address (real USDS for the Ethereum pair, mock USDS for the Chiado pair, as in D3). Every `UserRequestForSignature` then carries USDS and the foreign bridge pays USDS by plain transfer. No `usdsDepositContract` is set. `XDaiForeignBridge` on Ethereum stays unpatched; its DAI branch remains in the bytecode but is not reached. Foreign-to-home deposits are USDS-only already. |

---

## 3. Actions

### Phase 0 — Prerequisites (owner: user)

- [ ] Fund the deployer on **Chiado** (faucet xDAI) and **Ethereum** (real ETH; size after the gas estimate in Phase 2).
- [ ] Fund the deployer on both rollups by bridging from L1: `bridgeEther` on the EEZ bridge through `…/composer/l1`, or the dashboard at `https://eez.dev/dashboard/` and `https://rollupx.eez.dev/dashboard/`. No L2 gas faucet exists.
- [x] Answer D1–D10 (done 2026-11-23, see section 2).
- [x] Settle O1–O4 (done 2026-11-23).
- [ ] Confirm the repo may be created at `gnosischain/eez-gnosisbridge-deploy` and whether it is public or private. The name is free and the logged-in `gh` account is an active org member; repo-creation rights were not tested.

### Phase 1 — Repository (`gnosischain/eez-gnosisbridge-deploy`)

- [ ] Install Foundry on this machine (not installed today) and pin its version in the repo.
- [ ] Create the repo with `.gitignore` covering `.env`, `INSTRUCTION.md`, `broadcast/**/dry-run`, `cache`, `out`.
- [ ] Add git submodules pinned to the commits in 1.3:
  - `lib/omnibridge` at `65ee7afb`
  - `lib/tokenbridge-xdai` at `52afd25b`
  - `lib/tokenbridge-amb` at `47873407`
  - `lib/forge-std`
- [ ] Install each submodule's npm dependencies with a lockfile (`openzeppelin-solidity@1.12.0`, `@openzeppelin/contracts@3.2.2-solc-0.7`).
- [ ] One Foundry profile per source tree, matching upstream compiler settings so bytecode is comparable:
  - `amb`: solc 0.4.24, 200 runs, `byzantium`
  - `xdai`: solc 0.4.24 (plus 0.8.25 files), `byzantium`; check `HomeBridgeErcToNative` against the 24 KB limit
  - `omnibridge`: solc 0.7.5, 200 runs, `istanbul`
  - `deploy`: solc 0.8.x for scripts and tests, loading legacy artifacts with `vm.deployCode` / `vm.getCode`
- [ ] New contracts in `src/`:
  - `MockUSDS.sol` — ERC-20 named USDS with unrestricted `mint` (Chiado)
  - `MockERC20.sol` — Omnibridge test token (Chiado)
  - `BlockRewardStub.sol` (D2)
- [ ] Committed `.patch` files applied by a build step, with the patched trees kept separate from the pristine submodules:
  - `patches/amb-disable-hashi.patch` — `HASHI_IS_ENABLED = false` in the `master` tree (D1)
  - `patches/xdai-disable-hashi.patch` — same constant in the `xdaibridge` tree, both pairs (O1)
  - `patches/xdai-chiado-mock-usds.patch` — token constants for the Chiado pair only, foreign and home (D3)
  - `patches/xdai-ethereum-home-usds.patch` — home bridge `DAI` constant set to real USDS, Ethereum pair only (O4)
- [ ] The xDAI tree is therefore built twice: once with the Chiado patch (testnet pair) and once with the Ethereum home patch (Ethereum pair).
- [ ] `config/chiado-rollupx-testnet.toml` and `config/ethereum-rollupx.toml` holding chain IDs, RPC names, roles, token name suffixes and the production parameter values (D8, O3). Secrets only via `.env`.
- [ ] `Makefile` targets: `build`, `test`, `deploy-<pair>`, `verify-<pair>`, `check-<pair>`.
- [ ] `README.md` with the exact reproduction steps and a `deployments/<pair>.json` address book written by the scripts.

### Phase 2 — Deploy scripts (Foundry, one entry point per pair)

Order per pair. Every step is idempotent: skip if the address in `deployments/<pair>.json` already has code.

1. **Pre-deploy**
   - [ ] Read the production parameters from the live Ethereum and Gnosis Chain contracts (AMB, xDAI bridge, Omnibridge) and commit them to both config files (D8).
   - [ ] Chiado only: `MockUSDS` through the CREATE2 deployer with a fixed salt (its address feeds the D3 patch), and `MockERC20`.
   - [ ] Home: `BlockRewardStub`.
2. **AMB** (`master`), home then foreign
   - [ ] `EternalStorageProxy` + `BridgeValidators`, `initialize(1, [validator], owner)`.
   - [ ] `EternalStorageProxy` + `HomeAMB` / `ForeignAMB`, `initialize(thisChainId, otherChainId, validators, maxGasPerTx, gasPrice, confirmations, owner)`.
   - [ ] Built from the Hashi-disabled tree (D1); no Hashi manager is set.
3. **xDAI bridge** (`xdaibridge`)
   - [ ] Separate `BridgeValidators` proxy per side, as in production (D8).
   - [ ] Home: `HomeBridgeErcToNative` behind a proxy, initialised with `BlockRewardStub`. Testnet uses the build with the mock-USDS constant (D3).
   - [ ] Foreign: `XDaiForeignBridge` on both chains — patched build + mock USDS on Chiado (D3), real USDS on Ethereum (D4). No `initializeInterest`, no `BridgeRouter`, no `usdsDepositContract`.
4. **Omnibridge** (PR 6)
   - [ ] Token image from `precompiled/PermittableToken.json` on each side.
   - [ ] `TokenFactory` through `0x4e59…956C` on both sides with a distinct salt per mediator (D7, `script/DeployTokenFactory.s.sol`), `setTokenImage`, `setDeployer(mediator, true)`, transfer ownership to Owner.
   - [ ] Home: mediator proxy, `SelectorTokenGasLimitManager`, `MultiTokenForwardingRulesManager`, `HomeOmnibridge`, `initialize` with the home chain-name suffix (D8).
   - [ ] Foreign: mediator proxy, `ForeignOmnibridge`, `initialize` with the foreign chain-name suffix (D8). No `WETHOmnibridgeRouter` (D6).
   - [ ] Set request gas limit 850,000 for selectors `0x2ae87cdd` and `0xd522cfd7` on the home gas-limit manager (PR 6's recommendation; no script does it).
5. **Hand-over**
   - [ ] `transferProxyOwnership(owner)` on every proxy and `transferOwnership(owner)` on every ownable module.
   - [ ] `check-<pair>` script asserting, on live state: every owner and proxy admin is the Owner, the validator set is exactly the mock validator with threshold 1, mediators point at each other and at the right AMB, chain IDs are correct, and the deployer holds no role.

Before any broadcast: run each script against forks, record total gas per chain, and report the Ethereum cost so the deployer can be funded with the right amount.

### Phase 3 — Verification

- [ ] `forge verify-contract` with Standard JSON input for every address in `deployments/<pair>.json`, including proxies and constructor arguments.
  - RollupX testnet: `https://eez.dev/explorer/api`
  - RollupX: `https://rollupx.eez.dev/explorer/api`
  - Chiado: `https://gnosis-chiado.blockscout.com/api`
  - Ethereum: `https://eth.blockscout.com/api` (D10, Blockscout only)
- [ ] Patched contracts are verified from the patched source tree; the README lists which addresses differ from upstream and by which patch.
- [ ] `verify-<pair>` re-runs cleanly and ends by querying each address and failing if any is unverified.
- [ ] Whether the two EEZ explorers need the API key for verification submissions is untested; reads work without one.

### Phase 4 — Fork tests (Foundry)

Setup, per pair: `vm.createFork` for home and foreign, deploy with the same scripts as Phase 2 (or attach to live addresses once deployed), create a mock user with `makeAddr`, fund it with `vm.deal` / `deal`, `vm.recordLogs` on the source chain, `vm.prank(validator)` on the destination. No waiting for finality and no real oracle.

For each case assert the source-chain balance decrease, the source event, and the destination event.

| Bridge | Direction | User call | Source event | Validator call (pranked) | Destination event |
|---|---|---|---|---|---|
| AMB | foreign → home | `requireToPassMessage` | `UserRequestForAffirmation` | `HomeAMB.executeAffirmation(data)` | `AffirmationCompleted` with `status = true` |
| AMB | home → foreign | `requireToPassMessage` | `UserRequestForSignature` | `ForeignAMB.executeSignatures(data, sig)` | `RelayedMessage` with `status = true` |
| Omnibridge | foreign → home | `relayTokens(token, receiver, value)` | `TokensBridgingInitiated` | `executeAffirmation` | `NewTokenRegistered` (first time), `TokensBridged` |
| Omnibridge | home → foreign | `transferAndCall` on the bridged token | `TokensBridgingInitiated` | `executeSignatures` | `TokensBridged` |
| xDAI | foreign → home | `relayTokens(receiver, amount)` | `UserRequestForAffirmation` | `executeAffirmation(recipient, value, nonce)` | `AffirmationCompleted` + stub `AddedReceiver`; **recipient native balance unchanged** |
| xDAI | home → foreign, via `relayTokens` | `relayTokens(receiver)` payable | `UserRequestForSignature` | `executeSignatures(message, sig)` | `RelayedMessage`; recipient USDS balance increased (mock USDS on Chiado, real USDS on Ethereum); recipient DAI balance unchanged |
| xDAI | home → foreign, via plain transfer | native transfer to the bridge with empty calldata | `UserRequestForSignature` with `recipient = sender` | `executeSignatures(message, sig)` | same as above |

- Signature blob for `executeSignatures`: `abi.encodePacked(uint8(1), v, r, s)` over `keccak256("\x19Ethereum Signed Message:\n" ‖ len ‖ message)`. The test needs a validator it can sign for, so either `vm.sign` with a test key added as validator under `vm.prank(owner)`, or (AMB/Omnibridge home side only) plain `vm.prank(validator)`.
- xDAI home → foreign: the test builds the signed message from the fields of the emitted `UserRequestForSignature`, including its token address, and asserts that token is USDS (O4).
- xDAI home → foreign (D5): each test first runs a foreign → home deposit so the stub's recorded total covers the amount (O2). Also assert that the native coin left the user and went to `address(0)`, that a transfer above the recorded total reverts, and that a transfer with non-empty calldata reverts.
- Tokens: mock ERC-20 on Chiado; real WETH on the Ethereum fork; mock USDS on Chiado; real USDS on the Ethereum fork.
- Additional checks: bridged token address equals `predictTokenProxyAddress`, a second bridge of the same token does not redeploy, out-of-limit amounts are rejected, and a non-validator caller is rejected.
- PR 6's `test-e2e/base/E2EBase.sol` already implements the two-fork relay pattern and can be adapted.

### Phase 5 — Deliverables

- [ ] `deployments/chiado-rollupx-testnet.json` and `deployments/ethereum-rollupx.json` with addresses, transaction hashes and source commits.
- [ ] Explorer links showing every contract verified.
- [ ] Test report: `forge test` output for both pairs.
- [ ] README section listing the known mismatches from `INSTRUCTION.md` (native token not minted by the xDAI bridge, mock tokens on Chiado) and every deviation from upstream source: the Hashi patches (D1, O1), the `BlockRewardStub` (D2) and the Chiado mock-USDS patch (D3). Also state that the home-to-foreign xDAI direction burns native coin that the EEZ bridge minted (D5).

---

## 4. Suggested order of work

1. Phase 1 repo skeleton and getting all three trees to compile under Foundry — this confirms or refutes the unverified problems in 1.4.
2. Fork tests against script-deployed contracts for the Chiado pair, then the Ethereum pair.
3. Gas estimate → user funds the deployer.
4. Deploy and verify the Chiado pair, run `check`, review.
5. Deploy and verify the Ethereum pair only after explicit go-ahead, since it spends real ETH and is permanent.
