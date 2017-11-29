#
#DEV1 commands
#

dev1-build:
	@echo "Build dev1"
	MIX_ENV=dev1 mix release

dev1-start:
	@echo "Start dev1"
	_build/dev1/rel/epoch_elixir/bin/epoch_elixir start

dev1-stop:
	@echo "Stop dev1"

dev1-clean:
	@echo "Cleaned dev1"
	@rm -rf ./_build/dev1/
	@rm -rf ./priv1/

#
#DEV2 commands
#

dev2-build:
	@echo "Build dev2"
	MIX_ENV=dev2 mix release

dev2-start:
	@echo "Start dev2"
	_build/dev2/rel/epoch_elixir/bin/epoch_elixir start

dev2-stop:
	@echo "Stop dev2"

dev2-clean:
	@echo "Cleaned dev2"
	@rm -rf ./_build/dev2/
	@rm -rf ./priv2/

#
#DEV3 commands
#

dev3-build:
	@echo "Build dev3"
	MIX_ENV=dev3 mix release

dev3-start:
	@echo "Start dev3"
	_build/dev3/rel/epoch_elixir/bin/epoch_elixir start

dev3-stop:
	@echo "Stop dev3"

dev3-clean:
	@echo "Cleaned dev3"
	@rm -rf ./_build/dev3/
	@rm -rf ./priv3/


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

killall:
	@echo "Kill all beam processes"
	@pkill -9 beam || true
