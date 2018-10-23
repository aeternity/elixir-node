
export AEVM_EXTERNAL_TEST_DIR=aevm_external

#
# build commands
#

dev-build: TYPE=dev_build
dev-build: internal-build

dev-start: TYPE=dev_build
dev-start: internal-start

dev-stop: TYPE=dev_build
dev-stop: internal-stop

dev-clean: TYPE=dev_build
dev-clean: internal-clean

dev-attach: TYPE=dev_build
dev-attach: internal-attach

# prod

prod-build: TYPE=prod
prod-build: internal-build

prod-start: TYPE=prod
prod-start: internal-start

prod-stop: TYPE=prod
prod-stop: internal-stop

prod-clean: TYPE=prod
prod-clean: internal-clean

prod-attach: TYPE=prod
prod-attach: internal-attach

#
# internal commands
#

internal-build:
	@MIX_ENV=$(TYPE) mix release
	@mkdir -p ./_build/$(TYPE)/priv

internal-start:
	@./_build/$(TYPE)/rel/elixir_node/bin/elixir_node start

internal-stop:
	@./_build/$(TYPE)/rel/elixir_node/bin/elixir_node stop

internal-clean:
	@rm -rf ./_build/$(TYPE)/
	@rm -rf ./priv_$(TYPE)/

internal-attach:
	@_build/$(TYPE)/rel/elixir_node/bin/elixir_node attach

iex-node:
	@rm -rf apps/aecore/priv/rox_db_400$(NODE_NUMBER)
	@PERSISTENCE_PATH=apps/aecore/priv/rox_db_400$(NODE_NUMBER)/ PEER_KEYS_PATH=apps/aecore/priv/peerkeys_400$(NODE_NUMBER)/ SIGN_KEYS_PATH=apps/aecore/priv/signkeys_400$(NODE_NUMBER)/ PORT=400$(NODE_NUMBER) SYNC_PORT=300$(NODE_NUMBER) iex -S mix phx.server

#
# utility
#

iex-0: NODE_NUMBER=0
iex-0: iex-node

iex-1: NODE_NUMBER=1
iex-1: iex-node

iex-2: NODE_NUMBER=2
iex-2: iex-node

iex-3: NODE_NUMBER=3
iex-3: iex-node

iex-n: NODE_NUMBER=$(IEX_NUM)
iex-n: iex-node

clean:
	@rm -rf deps
	@rm -rf _build
	@mix clean

clean-deps: clean
	@mix deps.get
	@mix deps.compile || true
	# needed as duplicate for libsecp256k1 to compile
	@mix deps.compile

clean-deps-compile: clean-deps
	@mix compile

all-test:
	@mix format --check-formatted
	@mix compile --warnings-as-errors || true
	@mix compile.xref --warnings-as-errors
	@mix credo list
	@mix coveralls -u --exclude disabled

prod-release:
	@MIX_ENV=prod mix release --env=prod


killall:
	@echo "Kill all beam processes"
	@pkill -9 beam || true

.PHONY: \
	multinode-build, multinode-start, multinode-stop, multinode-clean \
	dev-build, dev-start, dev-stop, dev-attach, dev-clean \
	prod-build, prod-start, prod-stop, prod-attach, prod-clean \
	iex-0, iex-1, iex-2, iex-3, iex-n \
 	clean, clean-deps, killall \

	#
	# AEVM
	#
aevm-test-deps: $(AEVM_EXTERNAL_TEST_DIR)/ethereum_tests

$(AEVM_EXTERNAL_TEST_DIR)/ethereum_tests:
	@git clone https://github.com/ethereum/tests.git $(AEVM_EXTERNAL_TEST_DIR)/ethereum_tests
	@cd $(AEVM_EXTERNAL_TEST_DIR)/ethereum_tests && git checkout 1b019db88522abacfbd7ca03382f2bbffa5ae8f0
