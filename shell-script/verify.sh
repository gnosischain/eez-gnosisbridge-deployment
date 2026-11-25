#!/usr/bin/env bash
# Verifies every contract of a pair on Blockscout and then reports the verification state of each address.
#
#   ./shell-script/verify.sh chiado-rollupx-testnet [foreign|home|status]
#
# Verifier endpoints:
#   Chiado / Ethereum : Blockscout Pro API (https://api.blockscout.com/<chainId>/api), needs BLOCKSCOUT_API_KEY.
#                       The public gnosis-chiado.blockscout.com host answers scripts with a Cloudflare challenge.
#   RollupX           : the self-hosted explorers, no key. The Blockscout key is never sent to them.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.foundry/bin:$PATH"
set -a; [ -f .env ] && . ./.env; set +a

PAIR="${1:?usage: verify.sh <pair> [foreign|home|status]}"
WHAT="${2:-all}"
DIR="deployments/$PAIR"
F="$DIR/foreign.json"; H="$DIR/home.json"
DEPLOYER="${DEPLOYER:-0x652987962C5cb6660755a8432AA2526DD7a89366}"
OWNER=0xB4265633387DAe42a822c5DaF2f90C8d799C9455
ZERO=0x0000000000000000000000000000000000000000

case "$PAIR" in
  chiado-rollupx-testnet)
    XDAI=xdai-testnet; HOME_SUFFIX=" on RollupX Testnet"; FOREIGN_SUFFIX=" on Chiado"
    HOME_API=https://eez.dev/explorer/api ;;
  ethereum-rollupx)
    XDAI=xdai-mainnet; HOME_SUFFIX=" on RollupX"; FOREIGN_SUFFIX=" on Ethereum"
    HOME_API=https://rollupx.eez.dev/explorer/api ;;
  *) echo "unknown pair $PAIR"; exit 1 ;;
esac
FOREIGN_CHAIN=$(jq -r .chainId "$F"); HOME_CHAIN=$(jq -r .chainId "$H")
FOREIGN_API="https://api.blockscout.com/$FOREIGN_CHAIN/api"

f() { jq -r ".$1" "$F"; }
h() { jq -r ".$1" "$H"; }

# verify <side> <address> <tree> <contract id> [abi-encoded constructor args]
verify() {
  local side="$1" addr="$2" tree="$3" id="$4" args="${5:-}"
  local root="$ROOT"; [ "$tree" = root ] || root="$ROOT/build/$tree"
  # --skip-is-verified-check: forge otherwise skips proxies and the token image as "already verified" when the
  # explorer only knows a similar bytecode. The status table printed at the end is the authoritative result.
  local cmd=(forge verify-contract "$addr" "$id" --root "$root" --verifier blockscout --skip-is-verified-check
    --watch --retries 8 --delay 5)
  if [ "$side" = foreign ]; then
    cmd+=(--chain-id "$FOREIGN_CHAIN" --verifier-url "$FOREIGN_API" --verifier-api-key "$BLOCKSCOUT_API_KEY")
  else
    cmd+=(--chain-id "$HOME_CHAIN" --verifier-url "$HOME_API")
  fi
  [ -n "$args" ] && cmd+=(--constructor-args "$args")
  printf '%-8s %-44s %s ... ' "$side" "${id##*:}" "$addr"
  "${cmd[@]}" 2>&1 | grep -E "already verified|Pass - Verified|Fail|Error|error" | head -1 | cut -c1-90 || true
}

PROXY=contracts/upgradeability/EternalStorageProxy.sol:EternalStorageProxy
VALIDATORS=contracts/upgradeable_contracts/BridgeValidators.sol:BridgeValidators
U=contracts/upgradeable_contracts

verify_foreign() {
  if [ "$(f mockToken)" != "$ZERO" ]; then
    verify foreign "$(f usds)" root src/MockERC20.sol:MockERC20 "$(cast abi-encode 'c(string,string,uint8)' USDS USDS 18)"
    verify foreign "$(f mockToken)" root src/MockERC20.sol:MockERC20 "$(cast abi-encode 'c(string,string,uint8)' 'EEZ Bridge Test Token' EBT 18)"
  fi
  verify foreign "$(f ambValidatorsImpl)" amb "$VALIDATORS"
  verify foreign "$(f ambValidators)" amb "$PROXY"
  verify foreign "$(f ambImpl)" amb "$U/arbitrary_message/ForeignAMB.sol:ForeignAMB"
  verify foreign "$(f amb)" amb "$PROXY"
  verify foreign "$(f xdaiValidatorsImpl)" "$XDAI" "$VALIDATORS"
  verify foreign "$(f xdaiValidators)" "$XDAI" "$PROXY"
  verify foreign "$(f xdaiBridgeImpl)" "$XDAI" "$U/erc20_to_native/XDaiForeignBridge.sol:XDaiForeignBridge"
  verify foreign "$(f xdaiBridge)" "$XDAI" "$PROXY"
  verify foreign "$(f tokenImage)" token-image contracts/PermittableToken.sol:PermittableToken \
    "$(cast abi-encode 'c(string,string,uint8,uint256)' '' '' 0 "$FOREIGN_CHAIN")"
  verify foreign "$(f tokenFactory)" omnibridge "$U/modules/factory/TokenFactory.sol:TokenFactory" \
    "$(cast abi-encode 'c(address,address)' "$DEPLOYER" "$ZERO")"
  verify foreign "$(f omnibridgeImpl)" omnibridge "$U/ForeignOmnibridge.sol:ForeignOmnibridge" \
    "$(cast abi-encode 'c(string)' "$FOREIGN_SUFFIX")"
  verify foreign "$(f omnibridge)" omnibridge "$PROXY"
}

verify_home() {
  verify home "$(h ambValidatorsImpl)" amb "$VALIDATORS"
  verify home "$(h ambValidators)" amb "$PROXY"
  verify home "$(h ambImpl)" amb "$U/arbitrary_message/HomeAMB.sol:HomeAMB"
  verify home "$(h amb)" amb "$PROXY"
  verify home "$(h xdaiValidatorsImpl)" "$XDAI" "$VALIDATORS"
  verify home "$(h xdaiValidators)" "$XDAI" "$PROXY"
  verify home "$(h blockReward)" root src/BlockRewardStub.sol:BlockRewardStub "$(cast abi-encode 'c(address)' "$(h xdaiBridge)")"
  verify home "$(h xdaiBridgeImpl)" "$XDAI" "$U/erc20_to_native/HomeBridgeErcToNative.sol:HomeBridgeErcToNative"
  verify home "$(h xdaiBridge)" "$XDAI" "$PROXY"
  verify home "$(h tokenImage)" token-image contracts/PermittableToken.sol:PermittableToken \
    "$(cast abi-encode 'c(string,string,uint8,uint256)' '' '' 0 "$HOME_CHAIN")"
  verify home "$(h tokenFactory)" omnibridge "$U/modules/factory/TokenFactory.sol:TokenFactory" \
    "$(cast abi-encode 'c(address,address)' "$DEPLOYER" "$ZERO")"
  verify home "$(h gasLimitManager)" omnibridge "$U/modules/gas_limit/SelectorTokenGasLimitManager.sol:SelectorTokenGasLimitManager" \
    "$(cast abi-encode 'c(address,address,uint256)' "$(h amb)" "$DEPLOYER" 600000)"
  verify home "$(h forwardingRulesManager)" omnibridge "$U/modules/forwarding_rules/MultiTokenForwardingRulesManager.sol:MultiTokenForwardingRulesManager" \
    "$(cast abi-encode 'c(address)' "$OWNER")"
  verify home "$(h omnibridgeImpl)" omnibridge "$U/HomeOmnibridge.sol:HomeOmnibridge" "$(cast abi-encode 'c(string)' "$HOME_SUFFIX")"
  verify home "$(h omnibridge)" omnibridge "$PROXY"
}

# status <side> <json>: asks the explorer for every address; returns non-zero if any is unverified.
status() {
  local side="$1" file="$2" base key bad=0
  if [ "$side" = foreign ]; then base="https://api.blockscout.com/$FOREIGN_CHAIN/api/v2"; key="?apikey=$BLOCKSCOUT_API_KEY"
  else base="${HOME_API}/v2"; key=""; fi
  while IFS='=' read -r name addr; do
    [ "$addr" = "$ZERO" ] && continue
    # The Pro API occasionally answers with a rate-limit body; retry before reporting "unverified".
    local r="" try
    for try in 1 2 3 4; do
      r=$(curl -s -m 30 "$base/smart-contracts/$addr$key" | jq -r '"\(.is_verified // false) \(.name // "-") \(if .is_partially_verified then "partial" else "full" end)"' 2>/dev/null)
      [[ "$r" == true* ]] && break
      sleep 3
    done
    printf '%-8s %-24s %s  %s\n' "$side" "$name" "$addr" "${r:-no answer}"
    [[ "$r" == true* ]] || bad=1
  done < <(jq -r 'to_entries[] | select(.key != "chainId") | "\(.key)=\(.value)"' "$file")
  return $bad
}

case "$WHAT" in foreign|all) verify_foreign ;; esac
case "$WHAT" in home|all) verify_home ;; esac

echo; echo "Verification state:"
rc=0
status foreign "$F" || rc=1
status home "$H" || rc=1
[ $rc -eq 0 ] && echo "ALL VERIFIED" || echo "SOME CONTRACTS ARE NOT VERIFIED"
exit $rc
