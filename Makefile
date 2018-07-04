#
# Multiple nodes
#

multinode-build: dev1-build
	@rm -rf _build/dev2 _build/dev3
	@for x in dev2 dev3; do \
		cp -R _build/dev1 _build/$$x; \
		cp rel/$$x/vm.args _build/$$x/rel/epoch_elixir/releases/0.1.0/vm.args; \
	done
	@make dev2-build
	@make dev3-build

multinode-start:
	@make dev1-start
	@make dev2-start
	@make dev3-start

multinode-stop:
	@make dev1-stop
	@make dev2-stop
	@make dev3-stop

multinode-clean:
	@make dev1-clean
	@make dev2-clean
	@make dev3-clean

#
# DEV1 commands
#

dev1-build: TYPE=dev1
dev1-build: internal-build

dev1-start: TYPE=dev1
dev1-start: internal-start

dev1-stop: TYPE=dev1
dev1-stop: internal-stop

dev1-clean: TYPE=dev1
dev1-clean: internal-clean

dev1-attach: TYPE=dev1
dev1-attach: internal-attach

#
# DEV2 commands
#

dev2-build: TYPE=dev2
dev2-build: internal-build

dev2-start: TYPE=dev2
dev2-start: internal-start

dev2-stop: TYPE=dev2
dev2-stop: internal-stop

dev2-clean: TYPE=dev2
dev2-clean: internal-clean

dev2-attach: TYPE=dev2
dev2-attach: internal-attach

#
# DEV3 commands
#

dev3-build: TYPE=dev3
dev3-build: internal-build

dev3-start: TYPE=dev3
dev3-start: internal-start

dev3-stop: TYPE=dev3
dev3-stop: internal-stop

dev3-clean: TYPE=dev3
dev3-clean: internal-clean

dev3-attach: TYPE=dev3
dev3-attach: internal-attach

#
# Internal commands
#

internal-build:
	@MIX_ENV=$(TYPE) mix release

internal-start:
	@./_build/$(TYPE)/rel/epoch_elixir/bin/epoch_elixir start

internal-stop:
	@./_build/$(TYPE)/rel/epoch_elixir/bin/epoch_elixir stop

internal-clean:
	@rm -rf ./_build/$(TYPE)/
	@rm -rf ./priv_$(TYPE)/

internal-attach:
	@_build/$(TYPE)/rel/epoch_elixir/bin/epoch_elixir attach

iex-node:
	@rm -rf apps/aecore/priv/rox_db_400$(NODE_NUMBER)
	@PERSISTENCE_PATH=apps/aecore/priv/rox_db_400$(NODE_NUMBER)/ PEER_KEYS_PATH=apps/aecore/priv/peerkeys_400$(NODE_NUMBER)/ AEWALLET_PATH=apps/aecore/priv/aewallet_400$(NODE_NUMBER)/ PORT=400$(NODE_NUMBER) SYNC_PORT=300$(NODE_NUMBER) iex -S mix phx.server

#
# Utility
#

iex-0: NODE_NUMBER=0
iex-0: iex-node

iex-1: NODE_NUMBER=1
iex-1: iex-node

iex-2: NODE_NUMBER=2
iex-2: iex-node

iex-3: NODE_NUMBER=3
iex-3: iex-node

clean:
	@rm -rf deps
	@rm -rf _build
	@mix clean

clean-deps: clean
	@mix deps.get
	@mix deps.compile || true
	# needed as duplicate for libsecp256k1 to compile
	@mix deps.compile

killall:
	@echo "Kill all beam processes"
	@pkill -9 beam || true

.PHONY: \
	multinode-build, multinode-start, multinode-stop, multinode-clean \
	dev1-start, dev1-stop, dev1-attach, dev1-clean \
	dev2-start, dev2-stop, dev2-attach, dev2-clean \
	dev3-start, dev3-stop, dev3-attach, dev3-clean \
	iex-0, iex-1, iex-2, iex-3 \
 	clean, clean-deps, killall \
