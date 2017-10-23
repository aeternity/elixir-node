[![Travis Build](https://travis-ci.org/aeternity/elixir-research.svg?branch=master)](https://travis-ci.org/aeternity/elixir-research)

# **Elixir blockchain research**

This is an elixir implementation of a basic blockchain. We aim to keep the blockchain as simple as possible and to research and experiment with different technologies 

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

## Prerequisites

To install and use the Elixir Blockchain you will need [Elixir](https://elixir-lang.org/install.html) and the source code by cloning or downloading the repository. 

## Usage
#### **Starting the application**
Start the application in interactive Elixir mode

`iex -S mix`
#### **Starting the miner**
To start the miner use the following command in the command prompt: 

`Aecore.Miner.Worker.resume()`

This will continuously mine new blocks until terminated or suspended.
To suspend/stop the miner from mining: 

`Aecore.Miner.Worker.suspend() `

#### **API calls**
To add block to the blockchain: 

`Aecore.Chain.Worker.add_block(%Block{}) :: :ok`

To get the all blocks in the current chain: 

`Aecore.Chain.Worker.all_blocks() :: list()`

To get latest block added to the chain: 

`Aecore.Chain.Worker.latest_block() :: %Block{}`

To get the latest chainstate: 

`Aecore.Chain.Worker.chain_state() :: map()`

To add transaction to the Transaction Pool:

`Aecore.Txs.Pool.Worker.add_transaction(%SignedTx{}) :: :ok | :error`

To remove transaction from the Transaction Pool: 

`Aecore.Txs.Pool.Worker.remove_transaction(%SignedTx{}) :: :ok | :error`

To inspect transactions in the Transaction Pool: 

`Aecore.Txs.Pool.Worker.get_pool() :: map() `

## Running the tests

To run the automatic tests:

`mix test`

## Logging 

To debug, see errors, warnings and info about the blockchain, 
the log can be found in the source folder under:`apps/aecore/logs`

`09:59:16.298 [info] Added block #1 with hash 6C449AC3B5E38857DC85310873979F45992270BF54304B3F60BE4F64373991B5, total tokens: 100 `

`09:59:16.298 [info] Mined block #1, difficulty target 1, nonce 4`

