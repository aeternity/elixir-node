dev1-build:
	@echo "Build dev1"

dev1-start:
	@echo "Start dev1"
	#_build/dev/rel/epoch_elixir/bin/epoch_elixir start
	
dev1-stop:
	@echo "Stop dev1"

dev2-build:
	@echo "Build dev1"

dev2-start:
	@echo "Start dev2"
	@PORT=4002 iex -S mix phx.server

dev2-stop:
	@echo "Stop dev2"

dev3-build:
	@echo "Build dev2"

dev3-start:
	@echo "Start dev3"
	@PORT=4002 iex -S mix phx.server

dev3-stop:
	@echo "Stop dev3"

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
