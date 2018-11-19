# aeternity Erlang implementation compatibility

## 0.16.0
### Checking Peering between 2 nodes, Sync and Gossiping Blocks/Txs
elixir-node must be run in production mode to use the`mean28s-generic` miner, by using `MIX_ENV=prod`.  

**To connect to a Epoch node:**
- Get the peer pubkey of the epoch node:
```erlang
(epoch)> {ok, PeerPubKey} = aec_keys:peer_pubkey().
(epoch)> erlang:display(PeerPubKey).
```
- Try to connect from the elixir node:
```elixir
iex> Peers.try_connect(%{host: 'localhost', port: 3015, pubkey: epoch_peer_key})
```

**To check that both nodes are connected, check if the top block is equal:**
- Get top block from epoch `aec_chain:top_block().`
- Get top block from elixir `Chain.top_block()`

**Check that we can gossip transactions between the implementations:**
- Create a `SpendTx`:
```elixir
iex> amount = 100
iex> fee = 10
iex> pubkey = <<0::256>>
iex> payload = <<>>
iex> Account.spend(pubkey, amount, fee, payload)
```
- Check if epoch has this transaction: `(epoch)> aec_tx_pool:size().` Should return 1, size is used, as there is no functionality to fetch the contents of the pool.

**Check that we can gossip blocks between the implementations:**
- Start both elixir and epoch nodes
- Stop epoch miner `(epoch)> aec_conductor:stop_mining().`
- Both nodes should be on Genesis Block
- Connect both nodes as described above
- Mine a block from elixir node
- Epoch node should be on block #1, check with `(epoch)> aec_chain:top_block().`

**Check that if one of the nodes is on longer chain, when connected with both implementations, the node with short chain will sync the longer remote chain:**

- Start both elixir and epoch nodes
- Both should be on Genesis block
- Start mining from epoch node until reaching block #10 with `(epoch)> aec_conductor:start_mining().`
- Start mining from elixir node until reaching block #6 with `iex> Miner.mine_sync_block_to_chain()`
- Connect the two nodes with the steps above
- Elixir node should be on block #10 after sync, with all blocks coming from epoch node

**Check that if on same height, the more difficult chain will be accepted by the other node (when on a fork, and with same top_block_height, the nodes decide on if their chain is superior by checking the difficulty)**

- Start both elixir and epoch nodes
- Both should be on Genesis block
- Start mining from both nodes
- Mine until block 5 is reached on both nodes
- Connect the two nodes as described above
- The node with lower difficulty will get the blocks from the other node

### Checking all transaction types with synced nodes:
**Be sure that both nodes are connected!**

Before checking transactions, mine a block to be sure there is sufficient balance, to cover for fees and transfer amounts.

If everything is correct in both nodes you have to have the same block for all following transaction types:
- In **epoch** you can check the top_block: `(epoch)> aec_chain:top_block().`
- In **elixir-node** you can check the top_block: `iex> Chain.top_block()`

#### Spend Transaction
- Create and mine a `SpendTx`:
```elixir
iex> amount = 100
iex> fee = 10
iex> pubkey = <<0::256>>
iex> payload = <<>>
iex> Account.spend(pubkey, amount, fee, payload)
iex> Miner.mine_sync_block_to_chain()
```

#### Naming Transactions
- Create and mine a `NamePreClaimTx`:
```elixir
iex> name = "foobar.test"
iex> name_salt = 100
iex> fee = 10
iex> ttl = 1000
iex> Account.pre_claim(name, name_salt, fee, ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameClaimTx`:
```elixir
iex> name = "foobar.test"
iex> name_salt = 100
iex> fee = 10
iex> ttl = 1000
iex> Account.claim(name, name_salt, fee, ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameUpdateTx`:
```elixir
iex> name = "foobar.test"
iex> pointers = "{\"account_pubkey\":\"ak_wvqpnQHuHSQq2hs7Q7zNPUiZmpYZAAQ9SemGHRhXjq6KXYmLa\"}"
iex> fee = 10
iex> expire_by = 10000
iex> client_ttl = 1000
iex> ttl = 1000
iex> Account.name_update(name, pointers, fee, expire_by, client_ttl, ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameTransferTx`:
```elixir
iex> name = "foobar.test"
iex> transfer_to_pub = <<92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 100, 132, 194>>
iex> fee = 10
iex> ttl = 1000
iex> Account.name_transfer(name, transfer_to_pub, fee, ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameRevokeTx`:
```elixir
iex> transfer_to_pub = <<92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 100, 132, 194>>
iex> amount = 100
iex> fee = 10
iex> payload = <<>>
iex> Account.spend(transfer_to_pub, amount, fee, payload)
iex> Miner.mine_sync_block_to_chain()
iex> next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1
iex> transfer_to_priv = <<205, 8, 195, 216, 100, 12, 253, 66, 144, 133, 18, 213, 67, 217, 4, 115, 143, 179, 32, 99, 119, 167, 63, 6, 234, 219, 85, 28, 23, 211, 153, 165, 92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 123, 132, 194>>
iex> name = "foobar.test"
iex> fee = 10
iex> ttl = 1000
iex> Account.name_revoke(transfer_to_pub, transfer_to_priv, name, fee, next_nonce, ttl)
iex> Miner.mine_sync_block_to_chain()
```

#### Oracle Transactions

- Create and mine a `RegisterOracleTx`:
```elixir
iex> query_format = "string"
iex> response_format = "string"
iex> query_fee = 10
iex> fee = 10
iex> ttl = %{ttl: 100, type: :relative}
iex> tx_ttl = 1000
iex> Oracle.register(query_format, response_format, query_fee, fee, ttl, tx_ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `QueryTx`:
```elixir
iex> {pub_key, _} = Keys.keypair(:sign)
iex> query_data = "Arbitrary question"
iex> query_fee = 10
iex> fee = 10
iex> query_ttl = %{ttl: 10, type: :relative}
iex> response_ttl = %{ttl: 20, type: :relative}
iex> tx_ttl = 1000
iex> Oracle.query(pub_key, query_data, query_fee, fee, query_ttl, response_ttl, tx_ttl)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `RespondTx`:
```elixir
iex> [txs] = Chain.top_block.txs
iex> tx = txs.data
iex> [sender] = tx.senders
iex> query_id = OracleQueryTx.id(sender.value, tx.nonce, tx.payload.oracle_address.value)
iex> response = "Answer to arbitrary question"
iex> fee = 10
iex> tx_ttl = 1000
iex> Oracle.respond(query_id, response, fee, tx_ttl)
iex> Miner.mine_sync_block_to_chain()
iex> tree_id = tx.payload.oracle_address.value <> query_id
iex> OracleStateTree.get_query(Chain.chain_state().oracles, tree_id)
```

- Create and mine a `ExtendTx`:
```elixir
iex> ttl = %{ttl: 100, type: :relative}
iex> fee = 10
iex> Oracle.extend(ttl, fee)
iex> Miner.mine_sync_block_to_chain()
```

#### Channel Transactions

##### Standard scenario

0. Start at least 2 Elixir nodes and 1 Epoch node. Both syncing with each other and epoch. 
1. (both) Set basic parameters: 

```elixir
iex> temporary_id = <<1,2,3>>
iex> initiator_pubkey = #Get from Keys.keypair(:sign) of corresponding node
iex> initiator_amount = 100
iex> responder_pubkey = #Get from Keys.keypair(:sign) of corresponding node
iex> responder_amount = 100
iex> locktime = 2
iex> channel_reserve = 5
iex> fee = 1
iex> {_, priv_key} = Keys.keypair(:sign)
```

2. (initiator) `Channel.initialize(temporary_id, initiator_pubkey, responder_pubkey, :initiator, channel_reserve)`
3. (responder) `Channel.initialize(temporary_id, initiator_pubkey, responder_pubkey, :responder, channel_reserve)`
4. (initiator) `{:ok, channel_id, half_signed_open_tx} = Channel.open(temporary_id, initiator_amount, responder_amount, locktime, fee, nonce, priv_key)` with appropriate nonce
5. Copy `half_signed_open_tx` to responder. You can do that by copy-pasting result of `IO.inspect(half_signed_open_tx, limit: :infinity)`
6. (responder) `{:ok, channel_id, fully_signed_open_tx} = Channel.sign_open(temporary_id, initiator_amount, responder_amount, locktime, half_signed_open_tx, priv_key)`
7. (responder) `Miner.mine_sync_block_to_chain()`
8. Check all nodes recognize new block **with** the ChannelOpenTx
9. Now the channel is considered to be open. You can check compatibility of any or multiple of the available operations described in the next section.
10. After testing the available operation close the channel.
11. (initiator) `{:ok, half_signed_close_tx} = Channel.close(channel_id, {5, 5}, nonce, priv_key)`
12. Copy `half_signed_close_tx` to responder
13. (responder) `{:ok, fully_signed_close_tx} = Channel.recv_close_tx(channel_id, half_signed_close_tx, {5, 5}, priv_key)`
14. (responder) `Miner.mine_sync_block_to_chain()`
15. Check all nodes recognize new block **with** the ChannelMutalCloseTx

##### Available operations on an open channel
These operations can be initiated by any party. Through the scope of this section we will refer to the party which started the operation as the first party.
###### Transfer:
1. (first party) `{:ok, half_signed_state} = Channel.transfer(channel_id, 50, priv_key)`
2. Copy `half_signed_state` to second party.
3. (second party) `{:ok, signed_state} = Channel.receive_half_signed_tx(half_signed_state, priv_key)`
4. Copy `signed_state` to first party.
5. (first party) `:ok = Channel.receive_fully_signed_tx(signed_state)`

###### Withdraw
1. (first party) `{:ok, half_signed_withdraw_tx} = Channel.withdraw(channel_id, amount, fee, nonce, priv_key)`
2. Copy `half_signed_withdraw_tx` to second party
3. (second party) `{:ok, fully_signed_withdraw_tx} = Channel.receive_half_signed_tx(half_signed_withdraw_tx, priv_key)`
4. Check if `fully_signed_withdraw_tx` is in the transaction pool and is recognised by all nodes in the network. 
5. Copy `fully_signed_withdraw_tx` to the first party
6. (first party) `:ok = Channel.receive_fully_signed_tx(fully_signed_withdraw_tx)`
7. Wait for the transaction to be mined. Make sure that all nodes recognise the new block with `fully_signed_withdraw_tx`. Make sure that the onchain channel total amount was changed `Chain.top_block_chain_state.channels |> PatriciaMerkleTree.print_debug`. 
8. (both parties) `:ok = Channel.receive_confirmed_tx(fully_signed_withdraw_tx)`

###### Deposit
1. (first party) `{:ok, half_signed_deposit_tx} = Channel.deposit(channel_id, amount, fee, nonce, priv_key)`
2. Copy `half_signed_deposit_tx` to second party
3. (second party) `{:ok, fully_signed_deposit_tx} = Channel.receive_half_signed_tx(half_signed_deposit_tx, priv_key)`
4. Check if `fully_signed_deposit_tx` is in the transaction pool and is recognised by all nodes in the network. 
5. Copy `fully_signed_deposit_tx` to the first party
6. (first party) `:ok = Channel.receive_fully_signed_tx(fully_signed_deposit_tx)`
7. Wait for the transaction to be mined. Make sure that all nodes recognise the new block with `fully_signed_withdraw_tx`. Make sure that the onchain channel total amount was changed `Chain.top_block_chain_state.channels |> PatriciaMerkleTree.print_debug`. 
8. (both parties) `:ok = Channel.receive_confirmed_tx(fully_signed_deposit_tx)`
    
##### Communication lost / party misbehaving scenario

0. Start 2 Elixir nodes. Both syncing with each other and epoch.
1. (both) Set basic parameters:
```elixir
iex> temporary_id = <<4,5,6>>
iex> initiator_pubkey = #Get from Keys.keypair(:sign) of corresponding node
iex> initiator_amount = 100
iex> responder_pubkey = #Get from Keys.keypair(:sign) of corresponding node
iex> responder_amount = 100
iex> locktime = 2
iex> channel_reserve = 5
iex> fee = 1
iex> {_, priv_key} = Keys.keypair(:sign)
```

2. (initiator) `Channel.initialize(temporary_id, initiator_pubkey, responder_pubkey, :initiator, channel_reserve)`
3. (responder) `Channel.initialize(temporary_id, initiator_pubkey, responder_pubkey, :responder, channel_reserve)`
4. (initiator) `{:ok, channel_id, half_signed_open_tx} = Channel.open(temporary_id, initiator_amount, responder_amount, locktime, fee, nonce, priv_key)` with appropriate nonce
5. Copy `half_signed_open_tx` to responder. You can do that by copy-pasting result of `IO.inspect(half_signed_open_tx, limit: :infinity)`
6. (responder) `{:ok, channel_id, fully_signed_open_tx} = Channel.sign_open(temporary_id, initiator_amount, responder_amount, locktime, half_signed_open_tx, priv_key)`
7. (responder) `Miner.mine_sync_block_to_chain()`
8. Check all nodes recognize new block **with** the ChannelOpenTx
9. Make a transfer as follows:

    a. (initiator) `{:ok, half_signed_state} = Channel.transfer(channel_id, 50, priv_key)`

    b. Copy `half_signed_state` to responder.

    c. (responder) `{:ok, signed_state} = Channel.receive_half_signed_tx(half_signed_state, priv_key)`

    d. Copy `signed_state` to initiator.

    e. (initiator) `:ok = Channel.receive_fully_signed_tx(signed_state)`

10. Make another partial transfer:

    a. (responder) `{:ok, half_signed_state2} = Channel.transfer(channel_id, 25, priv_key)`

    b. Copy `half_signed_state2` to initiator.

    c. (initiator) `{:ok, signed_state2} = Channel.receive_half_signed_tx(half_signed_state2, priv_key)`

    c. Do NOT copy `signed_state` to responder.

11. (responder) `Channel.solo_close(channel_id, 5, nonce, priv_key)` with appropriate nonce
12. (responder) `Miner.mine_sync_block_to_chain()` and check all nodes recognize ChannelSoloCloseTx.
13. (initiator) `Channel.slash(channel_id, 5, nonce, initiator_pubkey, priv_key)` with appropriate nonce
14. (initiator) `Miner.mine_sync_block_to_chain()` and check all nodes recognize ChannelSlashTx.
15. Mine 2 blocks.
16. (initiator) `Channel.settle(channel_id, 5, nonce + 1, priv_key)`
17. (initiator) `Miner.mine_sync_block_to_chain()` and check all nodes recognize ChannelSettleTx.

#### Contract Transactions

**Scenario using the following Solidity smart contract, containing getter and setter methods, (used calldata parameters are only applicable to this smart contract):**

```
pragma solidity ^0.4.0;

contract SimpleStorage {
    uint storedData;

    function set(uint x) public {
        storedData = x;
    }

    function get() public view returns (uint) {
        return storedData;
    }
}
```
**Note:**
- Sophia ABI and primitive operations are yet to be added
- Solidity events, logging and account creating, are not yet supported

In order to easily compile Solidity contracts, see their functions' signature hashes, etc., without any setup, [Remix IDE](https://remix.ethereum.org/) can be used.

- Create and mine a `ConcractCreateTx`:
```elixir
iex> code = State.bytecode_to_bin(
  "608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058200d4dc371ec3b51661664cbded4b6722edf12a97461796fe3ca14264502f265420029"
)
iex> vm_version = Constants.aevm_solidity_01()
iex> deposit = 100
iex> amount = 50
iex> gas = 100_000
iex> gas_price = 1
iex> call_data = <<>>
iex> fee = 10
iex> Contract.create(code, vm_version, deposit, amount, gas, gas_price, call_data, fee)
iex> Miner.mine_sync_block_to_chain()
```
- `code` is the byte code that the contract is compiled to

- `call_data` is the parameter that tells the VM which function to interpret, along with what parameter values to be passed

- depending on the `vm_version`, we can have a value, passed to a init function (Sophia), or be empty, like in this case (Solidity)

- Create and mine a `ContractCallTx` (set):
```elixir
iex> {pub_key, _} = Keys.keypair(:sign)
iex> prev_nonce = Chain.lowest_valid_nonce() - 1
iex> contract_id = Contract.create_contract_id(pub_key, prev_nonce)
iex> vm_version = Constants.aevm_solidity_01()
iex> amount = 50
iex> gas = 100_000
iex> gas_price = 1
iex> call_data = <<96, 254, 71, 177>> <> <<33::256>>
iex> call_stack = []
iex> fee = 10
iex> Call.call_contract(contract_id, vm_version, amount, gas, gas_price, call_data, call_stack, fee)
iex> Miner.mine_sync_block_to_chain()
```
- `call_stack` is used internally and should always be empty when executing from top level (populated automatically when there are nested calls)

- the first four bytes of `call_data` are the first four bytes of the Keccak-256 hash of the signature of the function (according to Solidity ABI); the next 32 bytes represent the value, which is to be passed to this function (arguments should be encoded, according to Solidity ABI); in this case, `<<96, 254, 71, 177>>` stands for the `set` function, and the next 32 bytes `<<33::256>>` represent the integer value of `33`

- Create and mine a `ContractCallTx` (get):
```elixir
iex> {pub_key, _} = Keys.keypair(:sign)
iex> prev_nonce = Chain.lowest_valid_nonce() - 2
iex> contract_id = Contract.create_contract_id(pub_key, prev_nonce)
iex> vm_version = Constants.aevm_solidity_01()
iex> amount = 50
iex> gas = 100_000
iex> gas_price = 1
iex> call_data = <<109, 76, 230, 60>>
iex> call_stack = []
iex> fee = 10
iex> Call.call_contract(contract_id, vm_version, amount, gas, gas_price, call_data, call_stack, fee)
iex> Miner.mine_sync_block_to_chain()
iex> prev_nonce = Chain.lowest_valid_nonce() - 1
iex> call_id = Call.id(pub_key, prev_nonce, contract_id)
iex> call_tree_id = CallStateTree.construct_call_tree_id(contract_id, call_id)
iex> CallStateTree.get_call(Chain.chain_state.calls, call_tree_id)
```

- `call_data` has a value of `<<109, 76, 230, 60>>`, which stands for the `get` function

- `call_stack` is again empty, as this is the top level call
