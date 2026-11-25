# Usage: make <target> PAIR=chiado-rollupx-testnet   (or PAIR=ethereum-rollupx)
SHELL := /bin/bash
export PATH := $(HOME)/.foundry/bin:$(PATH)
PAIR ?= chiado-rollupx-testnet
export PAIR

-include .env
export

# Optional extra flags, e.g. GAS_FLAGS="--with-gas-price 3gwei --priority-gas-price 1gwei" on Chiado.
GAS_FLAGS ?=
FORGE_SCRIPT = forge script foundry-script/Deploy.s.sol --private-key $(DEPLOYER_PRIVATE_KEY) --slow $(GAS_FLAGS)

.PHONY: build test test-deployed simulate-foreign deploy-foreign deploy-home deploy-finalize check verify

build:            ## export, patch and compile all trees
	./shell-script/build.sh

test:             ## fork tests: deploy on forks with the deploy code, then relay in both directions
	forge test -vv

test-deployed:    ## same tests against the live addresses in deployments/$(PAIR)/
	USE_DEPLOYED=true forge test -vv

deploy-foreign:   ## stage 1 (foreign chain)
	$(FORGE_SCRIPT) --sig "foreign()" --broadcast

deploy-home:      ## stage 2 (home chain)
	$(FORGE_SCRIPT) --sig "home()" --broadcast

deploy-finalize:  ## stage 3 (foreign chain)
	$(FORGE_SCRIPT) --sig "finalize()" --broadcast

check:            ## read-only assertions on both live chains
	forge script foundry-script/Deploy.s.sol --sig "check()"

verify:           ## verify every contract of the pair on Blockscout
	./shell-script/verify.sh $(PAIR)
