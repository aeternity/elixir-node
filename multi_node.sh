#!/bin/bash

PORT=4000 iex -S mix phx.server &
echo "Master node started"
sleep 1

if [ -z "$*" ]; then
  echo "Only master node started, enter number of nodes to be started";
fi

END=$1

for ((i=1; i<=END; i++)); do
  echo "Started elixir node on port: 400$i"
  (echo -e "Aecore.Peers.Worker.add_peer(\"0.0.0.0:4000\")") | PORT=400$i iex -S mix phx.server &
  sleep 3
done
