# About this release
This release is intended to be compatible with the [aeternity epoch 0.16.0](https://github.com/aeternity/epoch/releases/tag/v0.16.0) release. It includes all major features in the state of the development at that point with a few differences - state channel P2P logic isn't implemented and smart contracts don't support operations native to the Sophia language (Solidity smart contracts are still supported).

Please let us know if you have any problems by [opening an issue](https://github.com/aeternity/elixir-node/issues).

## Retrieve the software for running a node
A prebuilt release is available at https://github.com/aeternity/elixir-node/releases/tag/v0.1.0
## Running your node
After unpacking the contents of `elixir-node-0.1.0-ubuntu-x86_64.tar.gz`, the node can then be started with the following commands:

* Start the node in interactive mode - `./bin/elixir_node console`
* Start the node in the background - `./bin/elixir_node start`
* Connect to the console of the node running in the background - `./bin/elixir_node attach`
* Stop the node running in the background - `./bin/elixir_node stop`
## Configuring your node
Environment variables can be set at compile time by specifying the variable and it's value, for example:
`PORT=4000 ./bin/elixir_node console`

The following environment variables can be configured:
* PORT - the port on which the Phoenix server will listen for any HTTP requests
* SYNC_PORT - the port that will be used for any sync related P2P message receiving
* ACCOUNTS_PATH - path to the JSON file containing any preset account balances
* SIGN_KEYS_PASS - the password that will be used for private key encryption/decryption
* PEER_KEYS_PASS - the password that will be used for peer private key encryption/decryption
* PEER_KEYS_PATH - path to the peer key files
* SIGN_KEYS_PATH - path to the sign key files
* NEW_CANDIDATE_NONCE_COUNT - the number of mining attempts to be done before building a new block candidate
* PERSISTENCE_PATH - path to Rox database

It's possible to configure multiple environment variables, they should be separated with a space, for example:
`PORT=4000 SYNC_PORT=3016 ./bin/elixir_node console`
