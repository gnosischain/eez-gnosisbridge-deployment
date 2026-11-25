# DEPLOYMENT.md — changes and learnings

Record of what was built and deployed in this repository, what differs from `ACTION.md`, and what was learned on the way.
Both pairs are deployed: **Chiado ↔ RollupX testnet** on 2026-11-23 and **Ethereum ↔ RollupX** on 2026-11-24.

The Ethereum ↔ RollupX work (config change, test class, address books, broadcast files, this document) is in the working tree only; it has not been staged, committed or pushed.

## 1. Status

### Chiado ↔ RollupX testnet (2026-11-23)

| Step | Chiado (foreign, 10200) | RollupX testnet (home, 699169) |
|---|---|---|
| Deployed | yes, 32 transactions, 0 failed | yes, 36 transactions, 0 failed |
| Live check (`make check`) | passes | passes |
| Fork tests | 18 of 18 pass, both against a fresh fork deployment and against the live addresses | same |
| Verified on explorer | **14 of 14** | **0 of 15 — blocked by the explorer, see 5.1** |

Gas used: 22.7M on Chiado (about 0.023 xDAI at 1 gwei priority fee) and 24.6M on RollupX testnet (negligible at ~49 wei gas price).

### Ethereum ↔ RollupX (2026-11-24)

| Step | Ethereum (foreign, 1) | RollupX (home, 696991) |
|---|---|---|
| Deployed | yes, 30 transactions, 0 failed (one resent, see 5.7) | yes, 36 transactions, 0 failed |
| Deployment blocks | 26486214 – 26486252, plus the resent transaction in 26486295 | 1163461 – 1163503 |
| Live check (`make check PAIR=ethereum-rollupx`) | passes | passes |
| Fork tests | 18 of 18 pass, both against a fresh fork deployment and against the live addresses | same |
| Verified on explorer | **12 of 12** on `eth.blockscout.com` | **0 of 15 — blocked by the explorer, see 5.1** |

Gas used: 21,837,165 on Ethereum, costing **0.01116 ETH** at roughly 0.4–1.5 gwei, and 24,616,309 on RollupX, costing 1.23 gwei of ETH (1,230,815,450 wei) at 50 wei per gas.

Deployer balance afterwards: 0.0384 ETH on Ethereum and 8,769,184,550 wei on RollupX.

## 2. Addresses

Deployer `0x652987962C5cb6660755a8432AA2526DD7a89366`. Owner and proxy admin of everything: `0xB4265633387DAe42a822c5DaF2f90C8d799C9455`. Sole validator (threshold 1): `0xC18516Ce413cB899bC3f8bBA4c204bF97BE990E6`.

The address books are `deployments/chiado-rollupx-testnet/foreign.json` and `home.json`. Transaction hashes are in `broadcast/Deploy.s.sol/<chainId>/`.

### Chiado (foreign)

| Key | Address |
|---|---|
| `amb` | [`0xD973e95e7a1984FDEFBF7c6Cc32E967e6aD79Ac1`](https://gnosis-chiado.blockscout.com/address/0xD973e95e7a1984FDEFBF7c6Cc32E967e6aD79Ac1) |
| `ambImpl` | [`0x0Bbb04F132Ca55d11d9a6E24A79660D4EFCd5CC3`](https://gnosis-chiado.blockscout.com/address/0x0Bbb04F132Ca55d11d9a6E24A79660D4EFCd5CC3) |
| `ambValidators` | [`0xcD1a157099e68fD7f354f771c2917752Ffb0B023`](https://gnosis-chiado.blockscout.com/address/0xcD1a157099e68fD7f354f771c2917752Ffb0B023) |
| `ambValidatorsImpl` | [`0xE497d517504CAf9675a72cb5707E4d1c4bfEB1fD`](https://gnosis-chiado.blockscout.com/address/0xE497d517504CAf9675a72cb5707E4d1c4bfEB1fD) |
| `mockToken` | [`0x5C6E05dAfCf7F8fbcAED8F5DD19c416c4c3255A3`](https://gnosis-chiado.blockscout.com/address/0x5C6E05dAfCf7F8fbcAED8F5DD19c416c4c3255A3) |
| `omnibridge` | [`0x34b314ab13e89c7c654a485A6d8EE9cB68917136`](https://gnosis-chiado.blockscout.com/address/0x34b314ab13e89c7c654a485A6d8EE9cB68917136) |
| `omnibridgeImpl` | [`0x4B73C52897aE5202fe4F25eaA42d0A7A1ca29173`](https://gnosis-chiado.blockscout.com/address/0x4B73C52897aE5202fe4F25eaA42d0A7A1ca29173) |
| `tokenFactory` | [`0x88e1f2672F798bD4288A9959e3294c5e2748F12D`](https://gnosis-chiado.blockscout.com/address/0x88e1f2672F798bD4288A9959e3294c5e2748F12D) |
| `tokenImage` | [`0xf6aAA665Cc5EEF0DFDD1F0Db405C77F348C64035`](https://gnosis-chiado.blockscout.com/address/0xf6aAA665Cc5EEF0DFDD1F0Db405C77F348C64035) |
| `usds` | [`0xB691934cfF2030235195Db7b905d3Db9779fBFF6`](https://gnosis-chiado.blockscout.com/address/0xB691934cfF2030235195Db7b905d3Db9779fBFF6) |
| `xdaiBridge` | [`0x7C7B3770744Fe56E860F2846b22c75A749CD5E79`](https://gnosis-chiado.blockscout.com/address/0x7C7B3770744Fe56E860F2846b22c75A749CD5E79) |
| `xdaiBridgeImpl` | [`0x3D2312b94046792EBE00eB77cACf8Bd058F3B312`](https://gnosis-chiado.blockscout.com/address/0x3D2312b94046792EBE00eB77cACf8Bd058F3B312) |
| `xdaiValidators` | [`0xfC843A4624751B7aC196F0d8D38d9E11C9C714dc`](https://gnosis-chiado.blockscout.com/address/0xfC843A4624751B7aC196F0d8D38d9E11C9C714dc) |
| `xdaiValidatorsImpl` | [`0x48A31B5af89730786415E33123fe52f9F59e0258`](https://gnosis-chiado.blockscout.com/address/0x48A31B5af89730786415E33123fe52f9F59e0258) |

`usds` is the mock USDS (anyone can `mint`). `mockToken` is the Omnibridge test token "EEZ Bridge Test Token" (EBT), also freely mintable.

### RollupX testnet (home)

| Key | Address |
|---|---|
| `amb` | [`0x7423c8479fE83043b07685977c8dd85632B50fC0`](https://eez.dev/explorer/address/0x7423c8479fE83043b07685977c8dd85632B50fC0) |
| `ambImpl` | [`0xE2b140Ab543d9b93a9a7D4da78A86945A27212cA`](https://eez.dev/explorer/address/0xE2b140Ab543d9b93a9a7D4da78A86945A27212cA) |
| `ambValidators` | [`0xE708DA9F6De9a197243F5586eaEE4750F66e5b11`](https://eez.dev/explorer/address/0xE708DA9F6De9a197243F5586eaEE4750F66e5b11) |
| `ambValidatorsImpl` | [`0x509703Cf725191975506E5710f5a427f9799CCB3`](https://eez.dev/explorer/address/0x509703Cf725191975506E5710f5a427f9799CCB3) |
| `blockReward` | [`0x7C7B3770744Fe56E860F2846b22c75A749CD5E79`](https://eez.dev/explorer/address/0x7C7B3770744Fe56E860F2846b22c75A749CD5E79) |
| `forwardingRulesManager` | [`0xacD0e4B46cD2E83B20CB467494494126aEEa3013`](https://eez.dev/explorer/address/0xacD0e4B46cD2E83B20CB467494494126aEEa3013) |
| `gasLimitManager` | [`0x03b56d0a8cfA013093A1E0228a7c27Ce366FD1FA`](https://eez.dev/explorer/address/0x03b56d0a8cfA013093A1E0228a7c27Ce366FD1FA) |
| `omnibridge` | [`0x010e3f424FEf2f2FF858E147d4E750C46Ab7611a`](https://eez.dev/explorer/address/0x010e3f424FEf2f2FF858E147d4E750C46Ab7611a) |
| `omnibridgeImpl` | [`0x8a6cADfB581e30eD669ac3B80A437414Bc0049BC`](https://eez.dev/explorer/address/0x8a6cADfB581e30eD669ac3B80A437414Bc0049BC) |
| `tokenFactory` | [`0x44cc94FCee5318D7369fF0D81a4C5fB1C5Bfd95d`](https://eez.dev/explorer/address/0x44cc94FCee5318D7369fF0D81a4C5fB1C5Bfd95d) |
| `tokenImage` | [`0x34b314ab13e89c7c654a485A6d8EE9cB68917136`](https://eez.dev/explorer/address/0x34b314ab13e89c7c654a485A6d8EE9cB68917136) |
| `xdaiBridge` | [`0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED`](https://eez.dev/explorer/address/0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED) |
| `xdaiBridgeImpl` | [`0x634c12FF1a82E298eF0e5D23B8319c3CFD3Aa093`](https://eez.dev/explorer/address/0x634c12FF1a82E298eF0e5D23B8319c3CFD3Aa093) |
| `xdaiValidators` | [`0xDd753b50922A74a5365A124AA016f61A1BA871b0`](https://eez.dev/explorer/address/0xDd753b50922A74a5365A124AA016f61A1BA871b0) |
| `xdaiValidatorsImpl` | [`0x16917fD421Faa4CE5Df7DF2Ee6d5aCe048C433e7`](https://eez.dev/explorer/address/0x16917fD421Faa4CE5Df7DF2Ee6d5aCe048C433e7) |

Some addresses are identical on both chains but are **different contracts** (for example `0x7C7B…5E79` is the xDAI bridge proxy on Chiado and the block-reward stub on RollupX). This is because the same deployer started from nonce 0 on both chains. Always read an address together with its chain.

### Ethereum (foreign)

The address books are `deployments/ethereum-rollupx/foreign.json` and `home.json`.

| Key | Address |
|---|---|
| `amb` | [`0x0Bbb04F132Ca55d11d9a6E24A79660D4EFCd5CC3`](https://eth.blockscout.com/address/0x0Bbb04F132Ca55d11d9a6E24A79660D4EFCd5CC3) |
| `ambImpl` | [`0x7423c8479fE83043b07685977c8dd85632B50fC0`](https://eth.blockscout.com/address/0x7423c8479fE83043b07685977c8dd85632B50fC0) |
| `ambValidators` | [`0xE497d517504CAf9675a72cb5707E4d1c4bfEB1fD`](https://eth.blockscout.com/address/0xE497d517504CAf9675a72cb5707E4d1c4bfEB1fD) |
| `ambValidatorsImpl` | [`0xE708DA9F6De9a197243F5586eaEE4750F66e5b11`](https://eth.blockscout.com/address/0xE708DA9F6De9a197243F5586eaEE4750F66e5b11) |
| `omnibridge` | [`0xf6aAA665Cc5EEF0DFDD1F0Db405C77F348C64035`](https://eth.blockscout.com/address/0xf6aAA665Cc5EEF0DFDD1F0Db405C77F348C64035) |
| `omnibridgeImpl` | [`0x7d8Fb7AD55C3C4b85a3FCb49Af9F743A67f4666d`](https://eth.blockscout.com/address/0x7d8Fb7AD55C3C4b85a3FCb49Af9F743A67f4666d) |
| `tokenFactory` | [`0x88e1f2672F798bD4288A9959e3294c5e2748F12D`](https://eth.blockscout.com/address/0x88e1f2672F798bD4288A9959e3294c5e2748F12D) |
| `tokenImage` | [`0x8Fa91Be2f426cE03BD405044DA243A547b88166b`](https://eth.blockscout.com/address/0x8Fa91Be2f426cE03BD405044DA243A547b88166b) |
| `usds` | [`0xdC035D45d973E3EC169d2276DDab16f1e407384F`](https://eth.blockscout.com/address/0xdC035D45d973E3EC169d2276DDab16f1e407384F) |
| `xdaiBridge` | [`0x3D2312b94046792EBE00eB77cACf8Bd058F3B312`](https://eth.blockscout.com/address/0x3D2312b94046792EBE00eB77cACf8Bd058F3B312) |
| `xdaiBridgeImpl` | [`0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED`](https://eth.blockscout.com/address/0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED) |
| `xdaiValidators` | [`0x48A31B5af89730786415E33123fe52f9F59e0258`](https://eth.blockscout.com/address/0x48A31B5af89730786415E33123fe52f9F59e0258) |
| `xdaiValidatorsImpl` | [`0xDd753b50922A74a5365A124AA016f61A1BA871b0`](https://eth.blockscout.com/address/0xDd753b50922A74a5365A124AA016f61A1BA871b0) |

`usds` is the real USDS token, not deployed here. No mock tokens exist on this pair; the Omnibridge tests use WETH `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` as a plain ERC-20 (D6).

### RollupX (home)

| Key | Address |
|---|---|
| `amb` | [`0x7423c8479fE83043b07685977c8dd85632B50fC0`](https://rollupx.eez.dev/explorer/address/0x7423c8479fE83043b07685977c8dd85632B50fC0) |
| `ambImpl` | [`0xE2b140Ab543d9b93a9a7D4da78A86945A27212cA`](https://rollupx.eez.dev/explorer/address/0xE2b140Ab543d9b93a9a7D4da78A86945A27212cA) |
| `ambValidators` | [`0xE708DA9F6De9a197243F5586eaEE4750F66e5b11`](https://rollupx.eez.dev/explorer/address/0xE708DA9F6De9a197243F5586eaEE4750F66e5b11) |
| `ambValidatorsImpl` | [`0x509703Cf725191975506E5710f5a427f9799CCB3`](https://rollupx.eez.dev/explorer/address/0x509703Cf725191975506E5710f5a427f9799CCB3) |
| `blockReward` | [`0x7C7B3770744Fe56E860F2846b22c75A749CD5E79`](https://rollupx.eez.dev/explorer/address/0x7C7B3770744Fe56E860F2846b22c75A749CD5E79) |
| `forwardingRulesManager` | [`0xacD0e4B46cD2E83B20CB467494494126aEEa3013`](https://rollupx.eez.dev/explorer/address/0xacD0e4B46cD2E83B20CB467494494126aEEa3013) |
| `gasLimitManager` | [`0x03b56d0a8cfA013093A1E0228a7c27Ce366FD1FA`](https://rollupx.eez.dev/explorer/address/0x03b56d0a8cfA013093A1E0228a7c27Ce366FD1FA) |
| `omnibridge` | [`0x010e3f424FEf2f2FF858E147d4E750C46Ab7611a`](https://rollupx.eez.dev/explorer/address/0x010e3f424FEf2f2FF858E147d4E750C46Ab7611a) |
| `omnibridgeImpl` | [`0x8a6cADfB581e30eD669ac3B80A437414Bc0049BC`](https://rollupx.eez.dev/explorer/address/0x8a6cADfB581e30eD669ac3B80A437414Bc0049BC) |
| `tokenFactory` | [`0x44cc94FCee5318D7369fF0D81a4C5fB1C5Bfd95d`](https://rollupx.eez.dev/explorer/address/0x44cc94FCee5318D7369fF0D81a4C5fB1C5Bfd95d) |
| `tokenImage` | [`0x34b314ab13e89c7c654a485A6d8EE9cB68917136`](https://rollupx.eez.dev/explorer/address/0x34b314ab13e89c7c654a485A6d8EE9cB68917136) |
| `xdaiBridge` | [`0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED`](https://rollupx.eez.dev/explorer/address/0xF1E85f146b1EAfEeE0ed6F7e29dD1599286542ED) |
| `xdaiBridgeImpl` | [`0x634c12FF1a82E298eF0e5D23B8319c3CFD3Aa093`](https://rollupx.eez.dev/explorer/address/0x634c12FF1a82E298eF0e5D23B8319c3CFD3Aa093) |
| `xdaiValidators` | [`0xDd753b50922A74a5365A124AA016f61A1BA871b0`](https://rollupx.eez.dev/explorer/address/0xDd753b50922A74a5365A124AA016f61A1BA871b0) |
| `xdaiValidatorsImpl` | [`0x16917fD421Faa4CE5Df7DF2Ee6d5aCe048C433e7`](https://rollupx.eez.dev/explorer/address/0x16917fD421Faa4CE5Df7DF2Ee6d5aCe048C433e7) |

The RollupX addresses are **identical to the RollupX testnet addresses**, because the same deployer started from nonce 0 on both rollups. On Ethereum the deployer started from nonce 1, so the Ethereum addresses are shifted by one against Chiado: several of them equal a Chiado address of a different contract. Always read an address together with its chain.

## 3. How to reproduce

```
git submodule update --init          # sources pinned: omnibridge 65ee7afb, xdaibridge 52afd25b, master 47873407
cp .env.example .env                 # fill in the deployer key and the Blockscout key
make build                           # export + patch + compile all trees, checks code sizes
make test                            # fresh deployment on forks, then relays in both directions
make deploy-foreign GAS_FLAGS="--with-gas-price 3gwei --priority-gas-price 1gwei"   # stage 1, Chiado
make deploy-home                                                                    # stage 2, RollupX testnet
make deploy-finalize GAS_FLAGS="--with-gas-price 3gwei --priority-gas-price 1gwei"  # stage 3, Chiado
make check                           # read-only assertions on both live chains
make test-deployed                   # the same tests against the live addresses
make verify                          # verify everything, then print the state of every address
```

For the Ethereum pair every target takes `PAIR=ethereum-rollupx`, and no gas flags were needed:

```
make deploy-foreign  PAIR=ethereum-rollupx   # stage 1, Ethereum
make deploy-home     PAIR=ethereum-rollupx   # stage 2, RollupX
make deploy-finalize PAIR=ethereum-rollupx   # stage 3, Ethereum
make check           PAIR=ethereum-rollupx
make verify          PAIR=ethereum-rollupx
```

Toolchain: Foundry 1.8.5, Node 24 (only to fetch `openzeppelin-solidity@1.12.0` and `@openzeppelin/contracts@3.2.2-solc-0.7`, pinned by `package-lock.json`).

## 4. What was built

| Path | Purpose |
|---|---|
| `scripts/build.sh` | Exports each submodule with `git archive` into `build/<tree>/`, applies the patches, compiles with the upstream compiler settings. The submodules are never modified. |
| `patches/` | The four committed diffs listed in 4.1. |
| `src/MockERC20.sol` | Freely mintable ERC-20, used for the mock USDS and the Omnibridge test token. |
| `src/BlockRewardStub.sol` | Records what the home xDAI bridge asks to mint, emits `AddedReceiver`, transfers nothing. Only the bridge proxy can call it. |
| `script/lib/Config.sol` | Per-pair parameters (in Solidity rather than TOML, because the limits do not fit TOML integers). |
| `script/lib/BridgeDeployer.sol` | The deployment steps, shared by the broadcast script and the fork tests. |
| `script/lib/Checks.sol` | Post-deployment assertions: owners, proxy admins, validator set, limits, cross-chain links, Hashi off. |
| `script/Deploy.s.sol` | Entry points `foreign()`, `home()`, `finalize()`, `check()`. |
| `test/PairTest.sol` | Two-fork tests for AMB, Omnibridge and xDAI bridge in both directions, plus negative cases. |
| `test/ChiadoRollupXTestnet.t.sol`, `test/EthereumRollupX.t.sol` | One class per pair: config, fork blocks and the Omnibridge test token (mock token on Chiado, WETH on Ethereum). |
| `scripts/verify.sh` | Verifies every address and fails if any is left unverified. |

### 4.1 Deviations from upstream source

| Patch | Tree | Change |
|---|---|---|
| `amb-disable-hashi.patch` | `master` (AMB) | `HASHI_IS_ENABLED = false` (D1) |
| `xdai-disable-hashi.patch` | `xdaibridge` | `HASHI_IS_ENABLED = false` (O1) |
| `xdai-chiado-mock-usds.patch` | `xdaibridge`, testnet build | Mainnet USDS replaced by the mock USDS in `XDaiForeignBridge` and `SavingsDaiConnector`; home bridge `DAI` **and** `USDS` constants set to the mock USDS (D3, O4, and learning 5.3) |
| `xdai-ethereum-home-usds.patch` | `xdaibridge`, mainnet build | Home bridge `DAI` constant set to real USDS (O4). Deployed on RollupX. |

The Omnibridge (PR 6) is unpatched.

### 4.2 Parameters

Read from the live production contracts on 2026-11-23 and used for both pairs as decided (D8).

| Bridge | Side | Source contract | Values |
|---|---|---|---|
| AMB | foreign | Ethereum `0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e` | maxGasPerTx 4,000,000; gasPrice 10 gwei; confirmations 175 |
| AMB | home | Gnosis `0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59` | maxGasPerTx 2,000,000; gasPrice 0; confirmations 100 |
| xDAI | foreign | Ethereum `0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016` | daily 10,000,000; max 9,999,999; min 0.005; execution daily 15,000,000; execution max 10,000,000; gasPrice 100 gwei; confirmations 20 |
| xDAI | home | Gnosis `0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6` | daily 10,000,000 + 1 wei; max 10,000,000; **min 10**; execution daily 15,000,000; execution max 9,999,999; gasPrice 0; confirmations 20 |
| Omnibridge | foreign | Ethereum `0x88ad09518695c6c3712AC10a214bE5109a655671` | daily 1e37 + 10; max 1e36; min 1 wei; request gas limit 2,000,000 |
| Omnibridge | home | Gnosis `0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d` | daily 1e37 + 10; max 1e36; min 1e18; default request gas limit 600,000 |

Not copied from production:

- **Validators:** one mock validator, threshold 1.
- **Token name suffixes:** ` on RollupX Testnet` (home) and ` on Chiado` (foreign) for the testnet pair; ` on RollupX` and ` on Ethereum` for the Ethereum pair.
- **Omnibridge fee manager:** production has one on the home side; none is deployed here, so bridging is free.
- **Home xDAI minimum per transfer, Ethereum pair only:** 1 wei instead of 10 coins, which would be 10 ETH. The testnet pair keeps 10.
- **Home Omnibridge minimum per transfer, Ethereum pair only:** 1 wei instead of 1 token, which would be 1 WETH for a RollupX → Ethereum transfer. Set by the user on 2026-11-24. The testnet pair keeps 1 token.
- **Selector gas limits:** 850,000 for `0x2ae87cdd` and `0xd522cfd7` on the home gas limit manager, as PR 6 recommends for CREATE2 token deployment. Production has no selector overrides.

## 5. Learnings

### 5.1 RollupX explorers cannot verify contracts at the moment (open)

Investigated again on 2026-11-25, on both `eez.dev/explorer` and `rollupx.eez.dev/explorer` (Blockscout v9.0.2). The cause is on the explorer backend, not in the contracts or in the submitted sources:

- The verification config reports `is_rust_verifier_microservice_enabled: true` together with **zero** Solidity, Vyper, zk and Stylus compiler versions. With the microservice enabled, Blockscout takes these lists from the verifier microservice, so the backend is getting nothing back from it. On RollupX mainnet the config call takes about 32 seconds, which looks like a timeout towards that service.
- A submission of the plain solc 0.8.25 `BlockRewardStub` on RollupX mainnet is accepted, stays `Pending in queue` for about 15 seconds and ends in `Fail - Unable to verify`.
- The last successful verifications were 2026-11-07 (RollupX) and 2026-11-10 (testnet); none since on either explorer.
- **Where it is configured:** `docker-compose.explorers.yml` in [`eez-association/eez-rollupX`](https://github.com/eez-association/eez-rollupX/blob/main/docker-compose.explorers.yml) (runbook: `docs/runbooks/explorers.md`). The `blockscout` service sets `MICROSERVICE_SC_VERIFIER_ENABLED: "true"`, `MICROSERVICE_SC_VERIFIER_URL: http://verifier:8050/` and `MICROSERVICE_SC_VERIFIER_TYPE: sc_verifier` (lines 86–88). The `verifier` service (lines 32–37) is a self-hosted `ghcr.io/blockscout/smart-contract-verifier` container whose only setting is its listen address, so it uses the default compiler lists (`https://binaries.soliditylang.org/linux-amd64/list.json` for Solidity). The live frontend settings match this file.
- **So the settings themselves are correct**, and the list URL answers from the public internet. The fault is in the running `verifier` container: either it is not running, or it cannot reach the internet to download the compiler list and binaries. Which of the two is **not confirmed**; it needs the operator to look on the host (`docker compose -p eez-explorers ps verifier`, `logs verifier`, and `curl http://verifier:8050/api/v2/verifier/solidity/versions` from the `blockscout` container).

Earlier notes:

- Both the standard-JSON and the flattened-source methods are accepted (`Smart-contract verification started`) and then end in `Fail - Unable to verify`, also for a plain solc 0.8.25 contract.
- `https://eez.dev/explorer/api/v2/smart-contracts/verification/config` returns an **empty** `solidity_compiler_versions` list. The mainnet RollupX explorer returns the same empty list.
- Contracts on that explorer were verified as recently as 2026-11-10, so the verifier worked before.
- This needs the explorer operator. Once it is fixed, `./scripts/verify.sh chiado-rollupx-testnet home` submits all 15 home contracts and prints the result.
- The Blockscout Pro API key is for Blockscout-hosted explorers; it is not sent to the self-hosted `eez.dev` explorer.

### 5.2 Chiado verification needs the Blockscout Pro API host

`gnosis-chiado.blockscout.com/api` answers scripts with a Cloudflare challenge page. `https://api.blockscout.com/10200/api` with the API key works with `forge verify-contract --verifier blockscout`. Foundry sometimes reports "already verified" for proxies and the token image when the explorer does not agree; `--skip-is-verified-check` fixes that, and the status table printed by `verify.sh` is the authoritative result.

### 5.3 `usdsDepositContract` shares a storage slot with the proxy admin

In `HomeBridgeErcToNative`, `address public usdsDepositContract` is an ordinary state variable and lands in slot 6. In a freshly deployed `EternalStorageProxy`, slot 6 is `_upgradeabilityOwner`. Consequences on this deployment:

- `usdsDepositContract()` returns the proxy admin (the Owner). When the Owner sends coin to the bridge, the bridge writes its `USDS` constant into the message instead of `DAI`. That is why the testnet patch sets both constants to the mock USDS; a test covers it.
- **`setUSDSDepositContract` must never be called on this deployment.** It would overwrite the proxy admin with the given contract address.
- The production Gnosis Chain proxy is an older proxy with a different layout and does not have this collision (its slot 6 holds the deposit contract and its admin is elsewhere).

### 5.4 Code size

`XDaiForeignBridge` is 24,937 bytes at 200 optimizer runs, over the 24,576-byte limit. The xDAI tree is built with 10 runs, as in the upstream `foundry.toml` (23,603 bytes). `HomeOmnibridge` is 24,179 bytes at the upstream 200 runs, 397 bytes under the limit.

### 5.5 Three stages, not one script

The xDAI bridge and the Omnibridge each need the address of their counterpart at `initialize`, so the pair is deployed as foreign → home → foreign. Between stage 1 and stage 3 the two foreign proxies are uninitialised but safe: `initialize` only accepts the proxy admin.

### 5.6 Other findings

- **`ForeignAMB` and `XDaiForeignBridge` reject a zero gas price, the home contracts accept it.** Production home values are 0 and were copied.
- **Home xDAI minimum is 10 coins on the testnet pair.** Copied from production, so a home-to-foreign xDAI transfer below 10 native coins reverts there. On the Ethereum pair that would be 10 ETH, so the user set it to **1 wei** for that pair on 2026-11-24 (`Config.ethereumRollupX()`); every other limit still follows production.
- **`bridgeContractOnOtherSide()` is internal** on the foreign xDAI bridge; the check reads the storage slot instead.
- **The gas limit manager exposes `requestGasLimit()` and `requestGasLimit(bytes4)`** only; the underlying variables are internal.
- **The token image verifies from `precompiled/PermittableToken_flat.sol`** with solc 0.4.24, 200 runs, byzantium (partial match: only the metadata hash differs). `build.sh` asserts this on every build.
- **xDAI messages are 124 bytes** (recipient, value, nonce, foreign bridge, token) and the signed prefix contains the decimal length `124`. The tests build the message from the `UserRequestForSignature` event.
- **Chiado accepted a 1 gwei priority fee**; Foundry's own estimate was 1 wei, which was not tried.
- **The address book is only written on a real broadcast**, so a dry run cannot leave addresses of contracts that do not exist.
- **Fresh-deployment tests fork from the block before the live deployment** (Chiado 24142211, RollupX testnet 2272510, Ethereum 26486213, RollupX 1163460), because the CREATE2 contracts now exist on the live chains.
- **Home-to-foreign tests add a test validator** on the fork (pranked as Owner), because `executeSignatures` needs a real signature and the mock validator's key is not available to the tests.

### 5.7 Ethereum: a transaction can be left pending when the base fee rises mid-run

Foundry caps each transaction at about twice the base fee seen when the script starts. During stage 3 the Ethereum base fee rose from 0.38 gwei to 1.6 gwei, so the last transaction (`transferProxyOwnership` on the foreign Omnibridge, nonce 30, fee cap 0.755 gwei) stayed in the mempool. Foundry reported "Some transactions were discarded by the RPC node" and `make check` failed with `foreign Omnibridge: proxy admin`.

- It was resent with `cast send` using the same nonce, the same calldata taken from the broadcast file, and a 5 gwei fee cap: [`0xb9bf695685b9e8325294a6d8c91d34f1e774efdea8ef3d7f009550538fe30e25`](https://eth.blockscout.com/tx/0xb9bf695685b9e8325294a6d8c91d34f1e774efdea8ef3d7f009550538fe30e25).
- `broadcast/Deploy.s.sol/1/finalize-latest.json` therefore lists the replaced hash `0x61722b67…2847f` for that transaction and has only 3 receipts. The hash above is the one that was mined.
- `forge script --resume` did not work for this script (`Missing --fork-url field`), because the script selects its fork itself.
- To avoid this on Ethereum, pass a generous cap, for example `GAS_FLAGS="--with-gas-price 5gwei"`.
- Stage 3 is not re-runnable from the start once its `initialize` calls have landed, so a partly sent stage 3 has to be finished transaction by transaction.

## 6. What the tests cover

For each case: source-chain balance decrease, source event, destination event.

| Bridge | Direction | Result |
|---|---|---|
| AMB | foreign → home | `UserRequestForAffirmation` → `AffirmationCompleted(status = true)`, target called with the right `messageSender` |
| AMB | home → foreign | `UserRequestForSignature` → `RelayedMessage(status = true)` |
| Omnibridge | foreign → home | tokens locked, `TokensBridgingInitiated` → `NewTokenRegistered` + `TokensBridged`; bridged token is at the predicted CREATE2 address and named "… on RollupX Testnet" (testnet pair) or "… on RollupX" (Ethereum pair); a second transfer does not redeploy |
| Omnibridge | home → foreign | bridged token burnt → `TokensBridged`, locked tokens released |
| xDAI | foreign → home | USDS locked, `UserRequestForAffirmation` → stub `AddedReceiver` + `AffirmationCompleted`; **recipient native balance unchanged** |
| xDAI | home → foreign | via `relayTokens` and via plain transfer: coin sent to `address(0)`, `UserRequestForSignature` carries USDS → `RelayedMessage`, USDS received |

Negative cases: non-validator affirmation, signature from a non-validator, Omnibridge below minimum, xDAI home-to-foreign with nothing deposited, above the recorded deposits, below the minimum, plain transfer with calldata, and a direct call to the stub.

These are contract-level tests on forks. No real cross-chain transfer has been sent through the live contracts, and no oracle is running.

## 7. Open items

1. **RollupX and RollupX testnet verification** — blocked by the explorers (5.1). 15 contracts on each rollup are unverified. Once fixed: `./scripts/verify.sh ethereum-rollupx home` and `./scripts/verify.sh chiado-rollupx-testnet home`.
2. **No oracle and no live transfer** — on both pairs nothing relays messages, and no real transfer has been sent through the live contracts. Funds sent into the mainnet bridges stay locked until the validator relays them.
3. **Single validator on mainnet** — the Ethereum pair uses the one mock validator with threshold 1, as decided (O3, D9). Its key alone can release any USDS or WETH locked on Ethereum.
4. **Git** — the Ethereum ↔ RollupX work is not staged, committed or pushed. `INSTRUCTION.md` and `.env` are git-ignored because they contain the deployer key and the API key.
