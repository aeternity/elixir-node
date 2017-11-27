#DEV1 commands
dev1-build:
	@echo "Build dev1"
	MIX_ENV=dev mix release

dev1-start:
	@echo "Start dev1"
	PORT=4001 _build/dev/rel/epoch_elixir/bin/epoch_elixir start

dev1-stop:
	@echo "Stop dev1"

dev2-clean:
	@echo "Cleaned dev1"

#
#DEV2 commands
#

dev2-build:
	@echo "Build dev1"

dev2-start:
	@echo "Start dev2"
	#@PORT=4002 iex -S mix phx.server

dev2-stop:
	@echo "Stop dev2"

dev2-clean:
	@echo "Cleaned dev2"

#
#DEV3 commands
#

dev3-build:
	@echo "Build dev2"

dev3-start:
	@echo "Start dev3"
	#@PORT=4002 iex -S mix phx.server

dev3-stop:
	@echo "Stop dev3"

dev2-clean:
	@echo "Cleaned dev3"

#
#Other
#
multinode-start:
	@make dev1-start
	@make dev2-start
	@make dev3-start

multinode-stop:
	@make dev1-stop
	@make dev2-stop
	@make dev3-stop

killall:
	@echo "Kill all beam processes"
	@pkill -9 beam || true
