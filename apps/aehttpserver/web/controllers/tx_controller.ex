defmodule Aehttpserver.TxController do
  use Aehttpserver.Web, :controller
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Utils.Serialization, as: Serialization
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation

  def show(conn, params) do
   # IO.inspect params["account"]
    account_bin =
      params["account"]
      |> Base.decode16!()
    #IO.inspect account_bin
    user_txs = Pool.get_txs_for_address(account_bin, :no_hash)
    user_proof = Pool.get_txs_for_address(account_bin, :add_hash)
    IO.inspect user_proof
    if length(user_proof) == 0 do
      <<0::256>>
    else
      merkle_tree =
      for transaction <- user_txs do
        transaction_data_bin = :erlang.term_to_binary(transaction)
        {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
      end

      merkle_tree =
        merkle_tree
        |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
      end)
        IO.inspect merkle_tree
        user_result =
        for user_result <- user_proof do
          :gb_merkle_trees.merkle_proof(user_result.txs_hash,
            merkle_tree)
          IO.inspect user_result
        end
        case params["include_proof"]  do
          "true" ->
            json(conn , Enum.map(user_txs, fn(tx) ->
                  %{tx |
                    from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize)
                   } end))
            _ ->
            json(conn , Enum.map(user_proof, fn(tx) ->
                  %{tx | txs_hash: Serialization.hex_binary(tx.txs_hash, :serialize),
                    from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize)               } end))
        end
    end
  end
end
