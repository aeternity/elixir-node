[![Travis Build](https://travis-ci.org/aeternity/elixir-research.svg?branch=master)](https://travis-ci.org/aeternity/elixir-research)

# **Elixir blockchain research**

This is an elixir implementation of a basic blockchain. We aim to keep the blockchain as simple as possible and to research and experiment with different technologies

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

## Prerequisites

To install and use the Elixir Blockchain you will need [Elixir](https://elixir-lang.org/install.html), [Rust](https://www.rust-lang.org/install.html) (for RocksDB persistence) and the source code by cloning or downloading the repository.

## Usage
#### **Starting the application**
Start the application in interactive Elixir mode

`iex -S mix phx.server`

#### **Starting the miner**
To start the miner use the following command in the command prompt:

`Aecore.Miner.Worker.resume()`

This will continuously mine new blocks until terminated or suspended.
To suspend/stop the miner from mining:

`Aecore.Miner.Worker.suspend() `

#### **Oracle usage**
Start the node as oracle operator -  `IS_OPERATOR=true iex -S mix phx.server`

Registering an oracle:
  `Aecore.OraclePrototype.Oracle.register(query_format, response_format, description, fee, oracle_uri)`
  The query and response formats are treated as json schemas with which the queries and responses
  are validated. The passed oracle uri isn't part of the transaction that gets created when
  registering an oracle, but it is stored as an environment variable mapped to the corresponding
  oracle (transaction) hash. If a node wants to serve as an oracle operator, an oracle server
  should be set up to handle queries. One node can run multiple oracles.

  To list all registered oracles -  `Aecore.Chain.Worker.registered_oracles()`

Querying an oracle:
  `Aecore.OraclePrototype.Oracle.query(oracle_hash, query_data, query_fee, response_fee)`
  The oracle hash is the hash of the oracle registration transaction.This transaction
  includes two fees - a query fee which is processed as a normal fee which is given
  to the miner and a response fee which is given to the oracle as a way to cover
  his response transaction fee.

Oracle responses:
  Whenever a new block is mined and a query transaction that references one of our
  oracles is present, the query is posted to the corresponding oracle server.
  That server must post a response back to the node's `/oracle_response` endpoint
  ({"oracle_hash": oracle hash in hex, "response": response data, "fee": fee})

All transactions have to be mined in order to take effect.

#### **API calls**
To add a block to the blockchain:

`Aecore.Chain.Worker.add_block(%Block{}) :: :ok`

To get all blocks in the current chain:

`Aecore.Chain.Worker.all_blocks() :: list()`

To get the latest block added to the chain:

`Aecore.Chain.Worker.latest_block() :: %Block{}`

To get the latest chainstate:

`Aecore.Chain.Worker.chain_state() :: map()`

To add a transaction to the Transaction Pool:

`Aecore.Txs.Pool.Worker.add_transaction(%SignedTx{}) :: :ok | :error`

To remove a transaction from the Transaction Pool:

`Aecore.Txs.Pool.Worker.remove_transaction(%SignedTx{}) :: :ok | :error`

To inspect all transactions in the Transaction Pool:

`Aecore.Txs.Pool.Worker.get_pool() :: map() `

## Running the tests

To run the automatic tests:

`mix test`

## Logging

To debug, see errors, warnings and info about the blockchain,
the log can be found in the source folder under:`apps/aecore/logs`

`09:59:16.298 [info] Added block #1 with hash 6C449AC3B5E38857DC85310873979F45992270BF54304B3F60BE4F64373991B5, total tokens: 100 `

`09:59:16.298 [info] Mined block #1, difficulty target 1, nonce 4`

## HTTP-API

The node will run an http API at `localhost:4000`
