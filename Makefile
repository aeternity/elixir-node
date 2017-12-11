#
#Miltiple nodes
#

multinode-build:
	@make dev1-build
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
#DEV1 commands
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
#DEV2 commands
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
#DEV3 commands
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
#Internal commands
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

#
# Utility
#

killall:
	@echo "Kill all beam processes"
	@pkill -9 beam || true

.PHONY: \
	multinode-build, multinode-start, multinode-stop, multinode-clean \
	dev1-start, dev1-stop, dev1-attach, dev1-clean \
	dev2-start, dev2-stop, dev2-attach, dev2-clean \
	dev3-start, dev3-stop, dev3-attach, dev3-clean \
 	killall \
