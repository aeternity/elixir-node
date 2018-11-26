# About this release

This is a maintenance release. It includes the following changes:

* Changed commitment hash calculations in naming system, to be `Hash(NameHash(name) + name_salt)` instead of `Hash(Hash(name + name_salt))`.
* Added identifiers to `name` and `name_commitment` structures. 
* Changed base58 encoding delimiter from `'$'` with `'_'`.
* Upgraded IDNA library to introduce character and label validation according to IDNA 2008.
* Removed `.aet` from allowed naming registrars.
* Added `vm_version` field to `oracle` and `oracle_registration_tx` structures. 
* Added `response_ttl` to `oracle_response_tx`.
* Adjusted oracle serializations. Oracle query structure changes: added binary identifiers to senders and oracle owners.
* Implemented functionality for garbage collecting of transactions in the pool. Transactions with expired TTL(TTL < current top_height) are removed from the transaction pool.
* Added functionality to get base gas price for each transaction.

Here, you can find [installation](https://github.com/aeternity/elixir-node/blob/master/docs/release-notes/release-notes-0.1.0.md#install-dependencies) and [configuration](https://github.com/aeternity/elixir-node/blob/master/docs/release-notes/release-notes-0.1.0.md#configuring-your-node) guides.

## Retrieve the software for running a node
A prebuilt release is available at https://github.com/aeternity/elixir-node/releases/tag/v0.2.0

## Running your node
After unpacking the contents of `elixir-node-0.2.0-ubuntu-x86_64.tar.gz`, the node can then be started with the following commands:

* Start the node in interactive mode - `./bin/elixir_node console`
* Start the node in the background - `./bin/elixir_node start`
* Connect to the console of the node running in the background - `./bin/elixir_node attach`
* Stop the node running in the background - `./bin/elixir_node stop`