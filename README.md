[![Travis Build](https://travis-ci.org/aeternity/elixir-node.svg?branch=master)](https://travis-ci.org/aeternity/elixir-node)

# Aeternity Elixir Full Node
This is an elixir full node implementation of the aeternity specification.

Compatibility to the erlang aeternity implementation is documented in [docs/aeternity-erlang-compatibility.md](docs/aeternity-erlang-compatibility.md).


## Getting started

### Required packages
[Elixir 1.6](https://elixir-lang.org/install.html) with Erlang/OTP20 is the basis of the project

[Rust](https://www.rust-lang.org/install.html) is needed for persistent storage dependency

libsodium 1.0.16 is needed for elliptic curve support
```bash
sudo apt-get install autoconf autogen libtool libgmp3-dev
wget -O libsodium-src.tar.gz https://github.com/jedisct1/libsodium/releases/download/1.0.16/libsodium-1.0.16.tar.gz
mkdir libsodium-src && tar -zxf libsodium-src.tar.gz -C libsodium-src --strip-components=1
cd libsodium-src && ./configure && make && make check && sudo make install && cd ..
```

#### Fetching dependencies
`mix deps.get`

#### Starting the application
Start the application in interactive Elixir
- Development config: `make iex-0`
- Production config: `MIX_ENV=prod make iex-0`

The default sync port is 3015, this can be adjusted using `SYNC_PORT=some_port iex -S mix phx.server`.
The node will run an http api at `localhost:4000`, this can be adjusted using `PORT=some_port iex -S mix phx.server`.

## Usage

### Elixir interactive api-calls
- `Miner.resume()` to start the miner
- `Miner.suspend() ` to stop the miner
- `Miner.mine_sync_block_to_chain()` mine the next block


- `Chain.top_block()` to get the top block of the current chain
- `Chain.top_block_chain_state()` to get the top block chainstate
- `Chain.chain_state(block_hash)` to get the chainstate of certain block


- `Pool.get_pool()` to get all transactions from the pool


- `Peers.all_peers()` to get all connected peers
- `Peers.try_connect(%{host: host, port: port, pubkey: pubkey})` to manually connect a new peer
- `Peers.get_info_try_connect(uri)` to connect to another elixir node, providing a get connection info interface

### Running the tests
Run the testsuite with `mix test`

### Logging
Debug, error, warning and info logs is found in `apps/aecore/logs`

### Docker Container
A `Dockerfile` and `docker-compose.yml` are found in the base directory, prebuilt images are not yet published.

 - Build container `docker build . -t elixir-node`
 - Run node in container `docker run --name elixir-node -it -p 4000:4000 -p 3015:3015 elixir-node`

 - Run multiple nodes network with docker compose `docker-compose up` runs 3 connected nodes, with 2 mining

## Detailed Usage

[docs/detailed-usage.md](docs/detailed-usage.md)

## Developer Documentation

[docs/developer-docs.md](docs/developer-docs.md)
