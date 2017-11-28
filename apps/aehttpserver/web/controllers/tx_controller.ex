defmodule Aehttpserver.TxController do
  use Aehttpserver.Web, :controller
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Utils.Serialization, as: Serialization
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.ChainState

  def show(conn, params) do
   # IO.inspect params["account"]
    account_bin =
      params["account"]
      |> Base.decode16!()
    #IO.inspect account_bin
    user_txs = Pool.get_txs_for_address(account_bin, :no_hash)
    user_proof = Pool.get_txs_for_address(account_bin, :add_hash)
    #IO.inspect user_proof
    merkle_tree =
      ChainState.calculate_chain_state_hash(Chain.chain_state)
    IO.inspect merkle_tree
    user_result =
   # for user_result <- user_proof do
      # :gb_merkle_trees.merkle_proof(user_result.block_hash,
     #   merkle_tree)
    #  IO.inspect user_result
   # end
    case params["include_proof"]  do
      "true" ->
        json(conn , Enum.map(user_txs, fn(tx) ->
              %{tx |
                from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                to_acc: Serialization.hex_binary(tx.to_acc, :serialize)
               } end))
      _ ->
        json(conn , Enum.map(user_proof, fn(tx) ->
              %{tx | block_hash: Serialization.hex_binary(tx.block_hash, :serialize),
                from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                to_acc: Serialization.hex_binary(tx.to_acc, :serialize)               } end))
    end
  end
end
