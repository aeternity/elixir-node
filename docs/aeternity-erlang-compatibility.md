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
iex> {:ok, tx} = Account.spend(pubkey, amount, fee, payload)
iex> Pool.add_transaction(tx)
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
iex> {:ok, tx} = Account.spend(pubkey, amount, fee, payload)
iex> Pool.add_transaction(tx)
iex> Miner.mine_sync_block_to_chain()
```

#### Naming Transactions
- Create and mine a `NamePreClaimTx`:
```elixir
iex> name = "foobar.aet"
iex> name_salt = 100
iex> fee = 10
iex> ttl = 1000
iex> {:ok, pre_claim} = Account.pre_claim(name, name_salt, fee, ttl)
iex> Pool.add_transaction(pre_claim)
iex> Miner.mine_sync_block_to_chain()
```
 
- Create and mine a `NameClaimTx`:
```elixir
iex> name = "foobar.aet"
iex> name_salt = 100
iex> fee = 10
iex> ttl = 1000
iex> {:ok, claim} = Account.claim(name, name_salt, fee, ttl)
iex> Pool.add_transaction(claim)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameUpdateTx`:
```elixir
iex> name = "foobar.aet"
iex> pointers = "{\"account_pubkey\":\"ak$wvqpnQHuHSQq2hs7Q7zNPUiZmpYZAAQ9SemGHRhXjq6KXYmLa\"}"
iex> fee = 10
iex> expire_by = 10000
iex> client_ttl = 1000
iex> ttl = 1000
iex> {:ok, update} = Account.name_update(name, pointers, fee, expire_by, client_ttl, ttl)
iex> Pool.add_transaction(update)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameTransferTx`:
```elixir
iex> name = "foobar.aet"
iex> transfer_to_pub = <<92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 100, 132, 194>>
iex> fee = 10
iex> ttl = 1000
iex> {:ok, transfer} = Account.name_transfer(name, transfer_to_pub, fee, ttl)
iex> Pool.add_transaction(transfer)
iex> Miner.mine_sync_block_to_chain()
```

- Create and mine a `NameRevokeTx`:
```elixir
iex> transfer_to_pub = <<92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 100, 132, 194>>
iex> amount = 100
iex> fee = 10
iex> payload = <<>>
iex> {:ok, spend} = Account.spend(transfer_to_pub, amount, fee, payload)
iex> Pool.add_transaction(spend)
iex> Miner.mine_sync_block_to_chain()
iex> next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1
iex> transfer_to_priv = <<205, 8, 195, 216, 100, 12, 253, 66, 144, 133, 18, 213, 67, 217, 4, 115, 143, 179, 32, 99, 119, 167, 63, 6, 234, 219, 85, 28, 23, 211, 153, 165, 92, 207, 73, 104, 187, 223, 191, 242, 179, 82, 37, 218, 72, 109, 92, 93, 40, 253, 163, 220, 208, 134, 169, 81, 69, 56, 212, 89, 81, 123, 132, 194>>
iex> name = "foobar.aet"
iex> fee = 10
iex> ttl = 1000
iex> {:ok, revoke} = Account.name_revoke(transfer_to_pub, transfer_to_priv, name, fee, next_nonce, ttl)
iex> Pool.add_transaction(revoke)
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
TBA..

#### Contract Transactions
TBA..