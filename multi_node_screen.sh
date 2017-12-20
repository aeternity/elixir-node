#!/bin/bash

# clean and compile the project
echo "clean and compile the project"
mix deps.get || exit 1 
mix clean || exit 1
mix compile || exit 1

# create screen and windows
echo "create screen and windows"
screen -S elixir-research -t PORT4000 -A -d -m
screen -S elixir-research -X screen -t PORT4001
screen -S elixir-research -X screen -t PORT4002

# start instances in different windows
echo "start nodes in screen"
screen -S elixir-research -p PORT4000 -X stuff $'PORT=4000 PERSISTENCE_PATH=apps/aecore/priv/rox_db_4000 iex -S mix phx.server -e "Aecore.Miner.Worker.resume"\n'
screen -S elixir-research -p PORT4001 -X stuff $'sleep 3; PORT=4001 PERSISTENCE_PATH=apps/aecore/priv/rox_db_4001 iex -S mix phx.server -e "Aecore.Peers.Worker.add_peer(\\""127.0.0.1:4000\\"")"\n'
screen -S elixir-research -p PORT4002 -X stuff $'sleep 3; PORT=4002 PERSISTENCE_PATH=apps/aecore/priv/rox_db_4002 iex -S mix phx.server -e "Aecore.Peers.Worker.add_peer(\\""127.0.0.1:4000\\"")"\n'

# attach screen
echo "attach nodes screen"
screen -r elixir-research
