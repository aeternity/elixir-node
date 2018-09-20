# Developer Documentation

## Makefile

- `make iex-0` to run interactive node with preconfigured ports and directories
- `make iex-1`, `make iex-2`, `make iex-3` to run configured nodes to be run in parallel
- `make clean` to clean project folders
- `make clean-deps` to clean project folders and compile deps
- `make clean-deps-compile` to clean project and compile deps and project
- `make killall` to kill all running elixir/erlang processes
- `make aevm-test-deps` to clone ethereum vm tests locally

## Debugging MerklePatriciaTree

To debug print the content `tree |> PatriciaMerkleTree.print_debug() ` can be used

## Building custom child transactions
To build a custom transaction you need to follow few simple steps:
- Make your own `transaction module`
- Create your `custom transaction structure`
- Override the `Transaction Behaviour` callbacks
- Write all your specific functions and checks inside your new `Transaction module`

All custom transactions are children to the `DataTx` Transaction that wraps them inside.
The DataTx structure hold:
- The name of your `transaction type` that should be you `Transaction Module name`
- The `payload` that will hold your `custom transaction structure`
- `sender`, `fee` and `nonce`
