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
sudo apt-get install autoconf autogen libtool libgmp3-dev
wget -O libsodium-src.tar.gz https://github.com/jedisct1/libsodium/releases/download/1.0.16/libsodium-1.0.16.tar.gz
mkdir libsodium-src && tar -zxf libsodium-src.tar.gz -C libsodium-src --strip-components=1
cd libsodium-src && ./configure && make && make check && sudo make install && cd ..
```

## Usage

#### **Fetching dependencies**
`mix deps.get`

#### **Starting the application**
Start the application in interactive Elixir mode

`iex -S mix phx.server`

#### **Starting the miner**
To start the miner use the following command in the command prompt:

`Miner.resume()`

This will continuously mine new blocks until terminated or suspended.
To suspend/stop the miner from mining:

`Miner.suspend() `

#### **Building custom child Transaction**
To build a custom transaction you need to follow few simple steps:
- Make your own `transaction module`
- Create your `custom transaction structure`
- Override the `Transaction Behaviour` callbacks
- Write all your specific functions and checks inside your new `Transaction module`

All custom transactions are childs to the `DataTx` Transaction that wraps them inside.
The DataTx strucure hold:
- The name of your `transaction type` that should be you `Transaction Module name`
- The `payload` that will hold your `custom transaction structure`
- `sender`, `fee` and `nonce`

### **API calls**

##### Chain :

- To get the top height of the current chain:

  `Chain.top_height()`

- To add get the top block of the current chain:

  `Chain.top_block()`

- To get the top block chain state:

  `Chain.top_block_chain_state()`

- To get the top block hash:

  `Chain.top_block_hash()`

- To get the latest chainstate:

  `Chain.chain_state()`

- To get the chainstate of certain block:

  `Chain.chain_state(block_hash)`

- To get a block from the local chain with certain hash

  `Chain.get_block_by_hex_hash(hash_of_a_block)`

- To get a block from memory or the database by certain hash:

  `Chain.get_block(hash_of_a_block)`

- To check if a certain block is in the local chain:

  `Chain.hash_block?(hash_of_a_block)`

- To get a certain number of blocks:

  `Chain.get_blocks(start_block_hash, number_of_blocks)`

- To get the longest chain:

  `Chain.longest_blocks_chain()`

##### Miner :

- To get a candidate block:

  `Miner.candidate()`

- To get the current value of the coinbase:

  `Miner.coinbase_transaction_value()`

- To get the current state of the miner:

  `Miner.get_state()`

##### Peers:
  The default sync port is 3015, it can be set manually by running the node with `SYNC_PORT=some_port iex -S mix`. This port is different from the one used by the phoenix server application.

- To get all peers:

  `Peers.all_peers()`

- Connect to a peer by specifying the address (host, has to be in single quotes i.e. 'localhost'), port (SYNC_PORT) and peer pubkey (different from the keypair which is used for transaction signing):

  `Peers.try_connect(%{host: host, port: port, pubkey: pubkey})`

- Connecting to a peer can also be done by using `Peers.get_info_try_connect(uri)` which gets the peer info from a phoenix endpoint (peer that is being added needs to have the phoenix server running).

##### Transaction Pool:

- To inspect all transactions in the Transaction Pool:

  `Pool.get_pool()`


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

  `POST localhost:4000/block`

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

#### **Oracle usage**
**TTL (time to live):**
  Determines the lifetime of an object measured in blocks, it can be either absolute
  or relative (absolute - the object is removed when a block with a height equal to the TTL is mined;
  relative - the object is removed when a block with height equal to the TTL + block height in which the transaction was included is mined). A TTL is defined like so - %{ttl: value, type: :relative | :absolute}

**Registering an oracle:**
  `Oracle.register(query_format, response_format, query_fee, fee, ttl)`
  The query and response formats are string descriptions of what the input for those should be. The query fee is the minimum fee that will be required for queries made to the oracle. If the oracle responds to the query on time, he will receive that fee as a compensation for the response fee he had to pay.

**Querying an oracle:**
  `Oracle.query(oracle_address, query_data, query_fee, fee, query_ttl, response_ttl)`
  The query TTL determines the time in which the oracle is able to respond, if he doesn't respond in time, the account making the query will get the query_fee back. The response TTL determines for how long the response will remain in the state after it is added, this TTL can only be relative.

  example query -
  ```
  Oracle.query(
    "ak$5oyDtV2JbBpZxTCS5JacVfPQHKjxCdoRaxRS93tPHcwvqTtyvz",
    "currency => USD",
     5,
     10,
     %{ttl: 10, type: :absolute},
     %{ttl: 5, type: :relative}
  )
  ```

**Respond to a query:**
  `Oracle.respond(query_id, response, fee)`
  Responds to a query which is referenced by ID, if the response is added successfully, the oracle receives the query_fee contained in the query.

**Extend a registered oracle:**
  `Oracle.extend(ttl, fee)`
  Extends the TTL of an oracle with the address that matches the address of the node.

All transactions have to be mined in order to take effect.

#### **Naming usage**

Names will follow IDNA2008 normalization and have a maximum length of 253 characters, while each label is allowed to be 63 characters maximum. Names must end with `.aet` or `.test`.

 * `NamePreClaim` a name, to register your interest in claiming it, while not announcing what name, a private binary salt is chosen. `Account.pre_claim(name, salt, fee)`
 * `NameClaim` is possible after one block to publicly claim the name by setting the owner `Account.claim(name, salt, fee)`. Claims expire after 50000 blocks, if not renewed using update.
 * `NameUpdate` updates associated pointers to one registered name, while updating the expiry. `Account.name_update(name, pointers, fee)`
 * `NameTransfer` transfers one account claim to a different owner. `Account.name_transfer(name, target, fee)`
 * `NameRevoke` revokes one name claim, will result in deletion after 2016 blocks. `Account.name_revoke(name, fee)`

#### **Channels usage**

##### Normal operation

For normal channel operation following procedure should be followed:

0. Parties negotiate channel properties (founds, accounts involved, locktime, channel\_reserve, temporary\_id)
1. Initiator calls `Channel.initialize(temporary_id, {{initiator_pubkey, initiator_amount}, {responder_pubkey, responder_amount}}, :initiator, channel_reserve)`
2. Responder calls `Channel.initialize(temporary_id, {{initiator_pubkey, initiator_amount}, {responder_pubkey, responder_amount}}, :responder, channel_reserve)`
3. Initiator calls `{:ok, channel_id, half_signed_open_tx} = Channel.open(temporary_id, locktime, fee, nonce, priv_key)`
4. Initiator sends `half_signed_open_tx` to Responder
5. Responder calls `{:ok, channel_id, fully_signed_open_tx} = Channel.sign_open(temporary_id, half_signed_open_tx, priv_key)`
6. Responder sends back `fully_signed_open_tx` to Initiator
7. Both parties await the transaction to be mined. Status of channel will get changed to `:open`
8. Both parties can create transactions as follows:

    a. First party calls `{:ok, half_signed_state} = Channel.transfer(channel_id, amount, priv_key)`
    b. First party sendd `half_signed_state` to second party.
    c. Second party calls `{:ok, signed_state} = Channel.recv_state(half_signed_state, priv_key)`
    c. Second party sends back `signed_state`
    d. First party calls `{:ok, nil} = Channel.recv_state(signed_state, priv_key)`
9. When parties negotiate that they want to close the channel any party (we will call it first party) calls `{:ok, half_signed_close_tx} = Channel.close(channel_id, {initiator_fee, responder_fee}, nonce, priv_key)`
10. First party sends `half_signed_close_tx` to second party
11. Second party calls `{:ok, fully_signed_close_tx} = Channel.recv_close_tx(channel_id, half_signed_close_tx, {initiator_fee, responder_fee}, priv_key)`
12. Second party sends `fully_signed_close_tx` to first party
13. When channel status changes to `:closed` channel is fully closed

##### Parameters description

- initiator\_pubkey, responder\_pubkey - pubkeys used for corresponding channel participants
- temporary\_id - any unique `binary()` for channel identification purposes before onchain id can be generated
- initiator\_amount, responder\_amount - amounts each participants want to commit to channel (integers)
- channel\_reserve - minimal amount to keep on both sides of channel (integer)
- fee, nonce - standard parameters for transactions generated by calls (integers)
- priv\_key - private key to sign the transaction or offchain state with, has to match the pubkey of party corresponding to node
- initiator\_fee, responder\_fee - fees for the ChannelMutalCloseTx to be subtracted from corresponding parties channel balance (integers)

##### Abnormal situation handling

If other party misbehaves and creates a `ChannelCloseSoloTx` with old state the party should call `Channel.slash(channel_id, fee, nonce, pubkey, priv_key)` (note: pubkey and privkey may be from another account then used to open the channel. One might send their ChannelStateOffChain to somebody else for safekeeping before going offline.)

If other party disappear or refuses to sign `ChannelCloseMutalTx` with up-to-date state the party should call `Channel.solo_close(channel_id, fee, nonce, priv_key)`.

When locktime is exhausted a party should call `Channel.settle(channel_id, fee, nonce, priv_key)` to close the channel.

Channel status can be checked with:
```
{:ok, state} = Channel.get_channel(channel_id)
state.fsm_state
```

#### **VM usage**

Initial implementation of the AEVM (Aeternity Virtual Machine) that contains all of the functionalities of the EVM (Ethereum Virtual Vachine).

To run the VM you can use the following command:
```
Aevm.loop(
    State.init_vm(
      %{
        :code => State.bytecode_to_bin("0x60013b"),
        :address => 0,
        :caller => 0,
        :data => <<0::256, 42::256>>,
        :gas => 100_000,
        :gasPrice => 1,
        :origin => 0,
        :value => 0
      },
      %{
        :currentCoinbase => 0,
        :currentDifficulty => 0,
        :currentGasLimit => 10000,
        :currentNumber => 0,
        :currentTimestamp => 0
      },
      %{},
      0,
      %{:execute_calls => true}
    )
  )
```

Where :code is the bytecode in hex that is going to be execute instruction by instruction

You can find each instruction(OP code) either from the file `op_codes.ex`,  [solidity opcodes section](http://solidity.readthedocs.io/en/v0.4.24/assembly.html) or from the tests.

Currently 629 tests pass from the official [EVM tests](http://ethereum-tests.readthedocs.io/en/latest/test_types/vm_tests.html)

Use command `make aevm-test-deps` to clone ethereum tests locally.
