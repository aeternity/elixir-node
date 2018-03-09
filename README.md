[![Travis Build](https://travis-ci.org/aeternity/elixir-node.svg?branch=master)](https://travis-ci.org/aeternity/elixir-node)

# **Aeternity Elixir Full Node**

This is an elixir full node implementation of the aeternity specification.


## Docker Container

A `Dockerfile` and `docker-compose.yml` are found in the base directory, prebuilt images are not yet published.

 - Build container `docker build . -t elixir-node`
 - Run node in container `docker run --name elixir-node -it -p 4000:4000 elixir-node`

 - Run multiple nodes network with docker compose `docker-compose up` runs 3 connected nodes, with 2 mining

## Getting started on your local machine

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

### Required packages

To install and use the Elixir Blockchain you will need [Elixir](https://elixir-lang.org/install.html), [Rust](https://www.rust-lang.org/install.html) (for RocksDB persistence) and the source code by cloning or downloading the repository.

Make sure you have installed the following packages to make sure that the Wallet will work properly:
```bash
sudo apt-get install autoconf autogen
sudo apt-get install libtool
sudo apt-get install libgmp3-dev
```

## Usage

#### **Fetching dependencies**
`mix deps.get`

#### **Starting the application**
Start the application in interactive Elixir mode

`iex -S mix phx.server`

#### **Starting the miner**
To start the miner use the following command in the command prompt:

`Aecore.Miner.Worker.resume()`

This will continuously mine new blocks until terminated or suspended.
To suspend/stop the miner from mining:

`Aecore.Miner.Worker.suspend() `

### **API calls**

##### Chain :

- To get the top height of the current chain:

  `Aecore.Chain.Worker.top_height()`

- To add get the top block of the current chain:

  `Aecore.Chain.Worker.top_block()`

- To get the top block chain state:

  `Aecore.Chain.Worker.top_block_chain_state()`

- To get the top block hash:

  `Aecore.Chain.Worker.top_block_hash()`

- To get the latest chainstate:

  `Aecore.Chain.Worker.chain_state()`

- To get the chainstate of certain block:

  `Aecore.Chain.Worker.chain_state(block_hash)`

- To get a block from the local chain with certain hash

  `Aecore.Chain.Worker.get_block_by_hex_hash(hash_of_a_block)`

- To get a block from memory or the database by certain hash:

  `Aecore.Chain.Worker.get_block(hash_of_a_block)`

- To check if a certain block is in the local chain:

  `Aecore.Chain.Worker.hash_block?(hash_of_a_block)`

- To get a certain number of blocks:

  `Aecore.Chain.Worker.get_blocks(start_block_hash, number_of_blocks)`

- To get the longest chain:

  `Aecore.Chain.Worker.longest_blocks_chain`

##### Miner :

- To get a candidate block:

  `Aecore.Miner.Worker.candidate()`

- To get the current value of the coinbase:

  `Aecore.Miner.Worker.coinbase_transaction_value()`

- To get the current state of the miner:

  `Aecore.Miner.Worker.get_state()`

##### Peers:

- To get all peers:

  `Aecore.Peers.Worker.all_peers()`

- To add peer:

  `Aecore.Peers.Worker.add_peer(uri)`

##### Transaction Pool:

- To inspect all transactions in the Transaction Pool:

  `Aecore.Txs.Pool.Worker.get_pool()`


### HTTP-API

- The node will run an http API at: `localhost:4000`

- To get the current info of the node:

  `GET localhost:4000/info`

- To get the peers your node is connected to:

  `GET localhost:4000/peers`

- To get all blocks from the current chain:

  `GET localhost:4000/blocks`  

- To get all blocks with full information about the blocks:

  `GET localhost:4000/raw_blocks`

- To get the transactions in the Transaction Pool:

  `GET localhost:4000/pool_txs`

- To post new transaction to the Transaction Pool:

  `POST localhost:4000/new_tx`

  Body: **serialized_tx**

  Where *serialized_tx* is json serialized signed transaction structure

- To post new block to the chain:

  `POST localhost:4000/new_block`

  Body: **serialized_block**

  Where *serialized_block* is a json serialized block structure

- To get all transactions for an account

  `GET localhost:4000/tx/{account}`

  Where *account* is a hex encoded public key

- To get a block by hash

  `GET localhost:4000/block/{block_hash}`

  Where *block_hash* is the bech32 encoded block header hash

- To get an account balance:

  `GET localhost:4000/balance/{account}`

  Where *account* is a hex encoded public key

- To get the transaction pool of an account:

  `GET localhost:4000/tx_pool/{account}`  

  Where *account* is a hex encoded public key

### Running the tests

To run the automatic tests:

`mix test`

### Logging

To debug, see errors, warnings and info about the blockchain,
the log can be found in the source folder under:`apps/aecore/logs`

`09:59:16.298 [info] Added block #1 with hash 6C449AC3B5E38857DC85310873979F45992270BF54304B3F60BE4F64373991B5, total tokens: 100 `

`09:59:16.298 [info] Mined block #1, difficulty target 1, nonce 4`
