END=$1
for ((i=1;i<=END;i++)); do
    echo "Started elixir node on port: 400$i"
    PORT=400$i iex -S mix phx.server &
    sleep 3
done
