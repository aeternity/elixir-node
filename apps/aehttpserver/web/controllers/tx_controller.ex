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
    user_txs = Pool.get_txs_for_address(account_bin, :no_hash)
    user_txs_and_hash = Pool.get_txs_for_address(account_bin, :add_hash)
    merkle_tree = build_tx_tree(user_txs)
    {size, {key, value, _}} = merkle_tree
    proof = :gb_merkle_trees.merkle_proof(key, merkle_tree)
    include_proof =
    for proof <- user_txs_and_hash do
      Map.put_new(proof, :proof, proof)
    end
    case params["include_proof"]  do
      "true" ->
        json(conn, Enum.map(include_proof, fn(tx) ->
              %{tx |
                proof: %{tx.proof |
                         from_acc: Serialization.hex_binary(tx.proof.from_acc, :serialize),
                         to_acc: Serialization.hex_binary(tx.proof.to_acc, :serialize),
                         txs_hash: Serialization.hex_binary(tx.proof.txs_hash, :serialize)},
                from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                to_acc: Serialization.hex_binary(tx.to_acc, :serialize),
                txs_hash: Serialization.hex_binary(tx.txs_hash, :serialize)
               } end))
      _ ->
        json(conn, Enum.map(user_txs, fn(tx) ->
              %{tx |
                from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                to_acc: Serialization.hex_binary(tx.to_acc, :serialize)
               } end))
    end
  end


  ## TODO : better use pattern matching for len checking : [_h | _] = txs
  defp build_tx_tree(txs) do
    if length(txs) == 0 do
      <<0::256>>
    else
      merkle_tree =
      for transaction <- txs do
        transaction_data_bin = :erlang.term_to_binary(transaction)
        {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
      end

      merkle_tree =
        merkle_tree
      |> List.foldl(:gb_merkle_trees.empty(), fn(node, merkle_tree_acc) ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree_acc)
      end)
    end
  end
end
