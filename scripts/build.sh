#!/usr/bin/env bash
# Builds the legacy bridge trees from the pinned submodules plus the committed patches.
#
#   build/amb            tokenbridge-contracts@master      + amb-disable-hashi            (solc 0.4.24)
#   build/xdai-testnet   tokenbridge-contracts@xdaibridge  + xdai-disable-hashi
#                                                          + xdai-chiado-mock-usds        (solc 0.4.24)
#   build/xdai-mainnet   tokenbridge-contracts@xdaibridge  + xdai-disable-hashi
#                                                          + xdai-ethereum-home-usds      (solc 0.4.24)
#   build/omnibridge     omnibridge PR 6, unpatched                                       (solc 0.7.5)
#   build/token-image    PermittableToken flattened source, for explorer verification     (solc 0.4.24)
#
# The submodules are never modified: each tree is exported with `git archive` into build/, patched there and
# compiled with its own foundry.toml. The root project loads the resulting artifacts with vm.getCode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.foundry/bin:$PATH"

[ -d node_modules/openzeppelin-solidity ] || npm ci --no-audit --no-fund

export_tree() { # <submodule> <tree> <patch>...
  local sub="$1" tree="$2"; shift 2
  rm -rf "build/$tree"
  mkdir -p "build/$tree"
  git -C "lib/$sub" archive HEAD contracts precompiled 2>/dev/null | tar -x -C "build/$tree" \
    || git -C "lib/$sub" archive HEAD contracts | tar -x -C "build/$tree"
  git -C "lib/$sub" rev-parse HEAD > "build/$tree/SOURCE_COMMIT"
  for p in "$@"; do
    echo "[$tree] applying patches/$p"
    patch -s -p1 -d "build/$tree" < "patches/$p"
  done
  mkdir -p "build/$tree/node_modules"
}

legacy_toml() { # <tree> <optimizer_runs>
  cat > "build/$1/foundry.toml" <<TOML
[profile.default]
src = "contracts"
out = "out"
cache_path = "cache"
libs = ["node_modules"]
remappings = ["openzeppelin-solidity/=node_modules/openzeppelin-solidity/"]
solc_version = "0.4.24"
evm_version = "byzantium"
optimizer = true
optimizer_runs = $2
TOML
}

# --- AMB (master) -----------------------------------------------------------------------------------------------
AMB_FILES=(
  contracts/upgradeability/EternalStorageProxy.sol
  contracts/upgradeable_contracts/BridgeValidators.sol
  contracts/upgradeable_contracts/arbitrary_message/HomeAMB.sol
  contracts/upgradeable_contracts/arbitrary_message/ForeignAMB.sol
)
export_tree tokenbridge-amb amb amb-disable-hashi.patch
cp -r node_modules/openzeppelin-solidity build/amb/node_modules/
legacy_toml amb 200
(cd build/amb && forge build --force "${AMB_FILES[@]}")

# --- xDAI bridge (xdaibridge) -----------------------------------------------------------------------------------
XDAI_FILES=(
  contracts/upgradeability/EternalStorageProxy.sol
  contracts/upgradeable_contracts/BridgeValidators.sol
  contracts/upgradeable_contracts/erc20_to_native/HomeBridgeErcToNative.sol
  contracts/upgradeable_contracts/erc20_to_native/XDaiForeignBridge.sol
)
build_xdai() { # <tree> <pair patch>
  export_tree tokenbridge-xdai "$1" xdai-disable-hashi.patch "$2"
  cp -r node_modules/openzeppelin-solidity "build/$1/node_modules/"
  # 10 runs as in the upstream foundry.toml: at 200 runs XDaiForeignBridge is 24937 bytes, over the EIP-170 limit.
  legacy_toml "$1" 10
  (cd "build/$1" && forge build --force "${XDAI_FILES[@]}")
}
build_xdai xdai-testnet xdai-chiado-mock-usds.patch
build_xdai xdai-mainnet xdai-ethereum-home-usds.patch

# --- Omnibridge (PR 6) ------------------------------------------------------------------------------------------
OMNI_FILES=(
  contracts/upgradeability/EternalStorageProxy.sol
  contracts/upgradeable_contracts/HomeOmnibridge.sol
  contracts/upgradeable_contracts/ForeignOmnibridge.sol
  contracts/upgradeable_contracts/modules/factory/TokenFactory.sol
  contracts/upgradeable_contracts/modules/gas_limit/SelectorTokenGasLimitManager.sol
  contracts/upgradeable_contracts/modules/forwarding_rules/MultiTokenForwardingRulesManager.sol
)
export_tree omnibridge omnibridge
mkdir -p build/omnibridge/node_modules/@openzeppelin
cp -r node_modules/@openzeppelin/contracts build/omnibridge/node_modules/@openzeppelin/
cat > build/omnibridge/foundry.toml <<TOML
[profile.default]
src = "contracts"
out = "out"
cache_path = "cache"
libs = ["node_modules"]
remappings = ["@openzeppelin/=node_modules/@openzeppelin/"]
solc_version = "0.7.5"
evm_version = "istanbul"
optimizer = true
optimizer_runs = 200
TOML
(cd build/omnibridge && forge build --force "${OMNI_FILES[@]}")

# --- Token image source (verification only) ---------------------------------------------------------------------
# The token image is deployed from the precompiled artifact. Its flattened source compiles to the same bytecode
# (apart from the metadata hash) with solc 0.4.24, 200 runs, byzantium, which is what the explorers verify against.
rm -rf build/token-image
mkdir -p build/token-image/contracts
cp lib/omnibridge/precompiled/PermittableToken_flat.sol build/token-image/contracts/PermittableToken.sol
cat > build/token-image/foundry.toml <<TOML
[profile.default]
src = "contracts"
out = "out"
cache_path = "cache"
libs = []
solc_version = "0.4.24"
evm_version = "byzantium"
optimizer = true
optimizer_runs = 200
TOML
(cd build/token-image && forge build --force)
built=$(jq -r '.bytecode.object' build/token-image/out/PermittableToken.sol/PermittableToken.json)
shipped=$(jq -r '.bytecode' build/omnibridge/precompiled/PermittableToken.json)
[ "${built:0:${#built}-86}" = "${shipped:0:${#shipped}-86}" ] \
  || { echo "ERROR: token image source does not match the precompiled artifact"; exit 1; }

# --- Root project (mocks, scripts, tests) -----------------------------------------------------------------------
forge build

# --- Size check (EIP-170: 24576 bytes of runtime code) ----------------------------------------------------------
echo
echo "Runtime code sizes (limit 24576 bytes):"
fail=0
for f in build/*/out/*/*.json; do
  n=$(basename "$f" .json)
  case "$n" in
    EternalStorageProxy|BridgeValidators|HomeAMB|ForeignAMB|HomeBridgeErcToNative|XDaiForeignBridge|HomeOmnibridge|ForeignOmnibridge|TokenFactory|SelectorTokenGasLimitManager|MultiTokenForwardingRulesManager) ;;
    *) continue ;;
  esac
  size=$(( ($(jq -r '.deployedBytecode.object' "$f" | wc -c) - 3) / 2 ))
  printf '  %-22s %-34s %6d\n' "$(echo "$f" | cut -d/ -f2)" "$n" "$size"
  [ "$size" -le 24576 ] || fail=1
done
[ "$fail" -eq 0 ] || { echo "ERROR: a contract exceeds the code size limit"; exit 1; }
