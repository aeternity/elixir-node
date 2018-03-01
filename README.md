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

#### **OnChainVoting**

*This part assumes you have aliased `Aecore.Structures.VotingOnChain` to `VotingOnChain`*

To create a new voting sign and submit question tx created with:

`VotingOnChain.create_question_tx(question, start_height, end_height, formula, initial_state)`
where:
- question - binary string representing the question asked
- start\_height - voting will be possible after top block reaches this height, question tx is valid only if block height <= start\_height
- end\_height - last block height when votes can be mined (a vote is valid if current block height is \>start\_height and <= end\_height)
- formula - binary reresenting the formula used in voting (see #) currently this can be one of the strings returned by:
    - `Aecore.Structures.VotingOnChain.code_single_choice` - for single choice per voter
    - `Aecore.Structures.VotingOnChain.code_multi_choice` - for multiple choices per voter 
- initial\_state - Initial state of voting contains information about choices. You can get it with:
    - `Aecore.Structures.VotingOnChain.get_single_choice_initial_state` for single\choice voting - with list of strings representing choices as parameter
    - `Aecore.Structures.VotingOnChain.get_single_choice_initial_state` for single\choice voting - with list of strings representing choices as parameter

Weight of the voting depends on the balances of accounts on start\_height (after tx at start\_height).

example:
`VotingOnChain.create_question_tx("The voting", Chain.top_height + 2, Chain.top_height + 3, VotingOnChain.code_single_choice, VotingOnChain.get_single_choice_initial_state(["a", "b", "c"]))`

To get voting hash:

`Voting.get_hash(voting_tx)`

where `voting_tx` is the question tx TxData.

To vote in single choice voting sign and submit tx created with:

`TxData.create(pk, voting_hash, 0, Chain.chain_state[pk].nonce + 1, 10, 0, %{choice: your_choice})`
where:
- pk - your pubkey
- voting\_hash - the hash of voting you would like to vote in
- your\_choice - string representing your choice (as in voting creation tx) 

To vote in multi choice voting sign and submit tx created with:

`TxData.create(pk, voting_hash, 0, Chain.chain_state[pk].nonce + 1, 10, 0, %{choices: list_of_your_choices})`
where:
- pk - your pubkey
- voting\_hash - the hash of voting you would like to vote in
- list\_of\_your\_choices - list of strings representing your choices (as in voting creation tx), for vote to validate all choices have to be valid

To get the state of voting (and results after voting is finished):

`Chain.chain_state()[voting_hash]` 

where voting\_hash is the hash of voting.

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
