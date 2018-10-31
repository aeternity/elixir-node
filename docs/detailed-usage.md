# Detailed Node Usage

## Oracle usage
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

## Naming usage

Names will follow IDNA2008 normalization and have a maximum length of 253 characters, while each label is allowed to be 63 characters maximum. Names must end with `.aet` or `.test`.

 * `NamePreClaim` a name, to register your interest in claiming it, while not announcing what name, a private binary salt is chosen. `Account.pre_claim(name, salt, fee)`
 * `NameClaim` is possible after one block to publicly claim the name by setting the owner `Account.claim(name, salt, fee)`. Claims expire after 50000 blocks, if not renewed using update.
 * `NameUpdate` updates associated pointers to one registered name, while updating the expiry. `Account.name_update(name, pointers, fee)`
 * `NameTransfer` transfers one account claim to a different owner. `Account.name_transfer(name, target, fee)`
 * `NameRevoke` revokes one name claim, will result in deletion after 2016 blocks. `Account.name_revoke(name, fee)`

## Channels usage

#### Normal operation

For normal channel operation following procedure should be followed:

0. Parties negotiate channel properties (founds, accounts involved, locktime, channel_reserve, temporary_id)
1. Initiator calls `Channel.initialize(temporary_id, {{initiator_pubkey, initiator_amount}, {responder_pubkey, responder_amount}}, :initiator, channel_reserve)`
2. Responder calls `Channel.initialize(temporary_id, {{initiator_pubkey, initiator_amount}, {responder_pubkey, responder_amount}}, :responder, channel_reserve)`
3. Initiator calls `{:ok, channel_id, half_signed_open_tx} = Channel.open(temporary_id, locktime, fee, nonce, priv_key)`
4. Initiator sends `half_signed_open_tx` to Responder
5. Responder calls `{:ok, channel_id, fully_signed_open_tx} = Channel.sign_open(temporary_id, half_signed_open_tx, priv_key)`
6. Responder sends back `fully_signed_open_tx` to Initiator
7. Both parties await the transaction to be mined. Status of channel will get changed to `:open`
8. Now the channel is opened and the parties can update the channel state. Currently you can perform one of these available operations:

    ##### Transfer:

    a. First party calls `{:ok, half_signed_offchain_tx} = Channel.transfer(channel_id, amount, priv_key)`
    
    b. First party should be now in the `:awaiting_full_tx` state
    
    c. First party sends `half_signed_offchain_tx` to second party.
    
    d. Second party calls `{:ok, fully_signed_offchain_tx} = Channel.receive_half_signed_tx(half_signed_offchain_tx, priv_key)`
    
    e. Second party should be now in the `:open` state
    
    f. Second party sends back `fully_signed_offchain_tx`
    
    g. First party calls `:ok = Channel.receive_fully_signed_tx(fully_signed_offchain_tx)`
    
    h. First party should be now in the `:open` state
    
    ##### Withdraw:
    
    a. First party calls `{:ok, half_signed_withdraw_tx} = Channel.withdraw(channel_id, amount, fee, nonce, priv_key)`
    
    b. First party should be now in the `:awaiting_full_tx` state
    
    c. First party sends `half_signed_withdraw_tx` to second party.
    
    d. Second party calls `{:ok, fully_signed_withdraw_tx} = Channel.receive_half_signed_tx(half_signed_withdraw_tx, priv_key)`
    
    e. Second party should be now in the `:awaiting_tx_confirmed` state
    
    f. `fully_signed_withdraw_tx` should be in the transaction pool.
    
    g. Second party sends back `fully_signed_withdraw_tx`
    
    h. First party calls `:ok = Channel.receive_fully_signed_tx(fully_signed_withdraw_tx)`
    
    i. First party should be now in the `:awaiting_tx_confirmed` state
    
    j. Both parties now await for the transaction to get enough confirmations
    
    k. When enough confirmations were made both parties call `:ok = Channel.receive_confirmed_tx(fully_signed_withdraw_tx)`
    
    l. Both parties should be in the `:open` state
    
    ##### Deposit:
    
    a. First party calls `{:ok, half_signed_deposit_tx} = Channel.deposit(channel_id, amount, fee, nonce, priv_key)`
    
    b. First party should be now in the `:awaiting_full_tx` state
    
    c. First party sends `half_signed_deposit_tx` to second party.
    
    d. Second party calls `{:ok, fully_signed_deposit_tx} = Channel.receive_half_signed_tx(half_signed_deposit_tx, priv_key)`
    
    e. Second party should be now in the `:awaiting_tx_confirmed` state
    
    f. `fully_signed_deposit_tx` should be in the transaction pool.
    
    g. Second party sends back `fully_signed_deposit_tx`
    
    h. First party calls `:ok = Channel.receive_fully_signed_tx(fully_signed_deposit_tx)`
    
    i. First party should be now in the `:awaiting_tx_confirmed` state
    
    j. Both parties now await for the transaction to get enough confirmations
    
    k. When enough confirmations were made both parties call `:ok = Channel.receive_confirmed_tx(fully_signed_deposit_tx)`
    
    l. Both parties should be in the `:open` state

9. When parties negotiate that they want to close the channel any party (we will call it first party) calls `{:ok, half_signed_close_tx} = Channel.close(channel_id, {initiator_fee, responder_fee}, nonce, priv_key)`
10. First party sends `half_signed_close_tx` to second party
11. Second party calls `{:ok, fully_signed_close_tx} = Channel.recv_close_tx(channel_id, half_signed_close_tx, {initiator_fee, responder_fee}, priv_key)`
12. Second party sends `fully_signed_close_tx` to first party
13. When channel status changes to `:closed` channel is fully closed

#### Parameters description

- initiator_pubkey, responder_pubkey - pubkeys used for corresponding channel participants
- temporary_id - any unique `binary()` for channel identification purposes before onchain id can be generated
- initiator_amount, responder_amount - amounts each participants want to commit to channel (integers)
- channel_reserve - minimal amount to keep on both sides of channel (integer)
- fee, nonce - standard parameters for transactions generated by calls (integers)
- priv_key - private key to sign the transaction or offchain state with, has to match the pubkey of party corresponding to node
- initiator_fee, responder_fee - fees for the ChannelMutalCloseTx to be subtracted from corresponding parties channel balance (integers)

#### Abnormal situation handling

If other party misbehaves and creates a `ChannelCloseSoloTx` with old state the party should call `Channel.slash(channel_id, fee, nonce, pubkey, priv_key)` (note: pubkey and privkey may be from another account then used to open the channel. One might send their ChannelStateOffChain to somebody else for safekeeping before going offline.)

If other party disappear or refuses to sign `ChannelCloseMutalTx` with up-to-date state the party should call `Channel.solo_close(channel_id, fee, nonce, priv_key)`.

When locktime is exhausted a party should call `Channel.settle(channel_id, fee, nonce, priv_key)` to close the channel.

Channel status can be checked with:
```
{:ok, state} = Channel.get_channel(channel_id)
state.fsm_state
```

## VM usage

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
