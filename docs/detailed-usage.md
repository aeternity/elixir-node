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

## Contracts usage

With every created contract, there is also a normal account with balance, to which we can perform spend transactions. All charges are being subtracted from the account of the creator/caller, before the call of the contract, together with gas*gas_price aeons. Each create/call will use up specific amount of gas, up to the maximum provided. Any remaining portion of gas will be refunded to the caller's account. If the initial call fails, amount and deposit are being returned to the creator.

The miner will add the newly created contract address and contract state to the state tree. The contract address is being generated, using the creator's address and nonce, at the time of the creation.

After calling a contract, a call object is being saved in the state tree, containing information about the execution.

**Creating a contract:**
  `Contract.create(code, vm_version, deposit, amount, gas, gas_price, call_data, fee, ttl)`
  Creates a contract with a given code. The initialization is done differently, depending on the vm_version. Owner of the contract will be the caller of the transaction.

**Creating a contract:**
  `Call.call_contract(contract, vm_version, amount, gas, gas_price, call_data, call_stack, fee, ttl)`
  Calls a contract under a given address. A call object will be saved in the state, containing gas used, return result and return type from this call.

#### Parameters description

- contract - the address of the contract
- code - the byte code of the contract
- vm_version - the VM/ABI to use
- deposit - to be held by the contract, until it is deactivated (an even number, 0 is accepted)
- amount - optional amount to transfer to the contract account before execution (even if the execution fails)
- gas - the amount of gas to use
- gas_price - gas price for the call
- call_data - call data for the (initial) call. Includes a function name and its arguments, which are to be interpreted. Encoded, according to the contract language's ABI
- call_stack - call stack (used internally for nested calls, empty when executing contract from top level)
