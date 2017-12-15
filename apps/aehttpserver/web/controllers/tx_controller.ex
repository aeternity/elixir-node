defmodule Aehttpserver.TxController do
  use Aehttpserver.Web, :controller
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Utils.Serialization, as: Serialization
  alias Aecore.Structures.TxData

  def show(conn, params) do
    account_bin =
      params["account"]
      |> Base.decode16!()
    user_txs = Pool.get_txs_for_address(account_bin)
    case user_txs do
      [] -> json(conn, [])
      _ ->
        case params["include_proof"]  do
          "true" ->
            blocks_for_user_txs =
            for user_tx <- user_txs do
              Pool.get_block_by_txs_hash(user_tx.txs_hash)
            end
            merkle_trees =
            for block <- blocks_for_user_txs do
              build_tx_tree(block.txs)
            end
            user_txs_trees = Enum.zip(user_txs, merkle_trees)
            proof =
            for user_tx_tree <- user_txs_trees  do
              {tx, tree} = user_tx_tree
              transaction = :erlang.term_to_binary(
                tx
                |> Map.delete(:txs_hash)
                |> Map.delete(:block_hash)
                |> Map.delete(:block_height)
                |> Map.delete(:signature)
                |> TxData.new()
                )
              key = :crypto.hash(:sha256, transaction)
              merkle_proof = :gb_merkle_trees.merkle_proof(key, tree)
              serialized_merkle_proof = serialize_merkle_proof(merkle_proof, [])
              verification =
                case :gb_merkle_trees.verify_merkle_proof(key, transaction, tx.txs_hash, merkle_proof) do
                  {:ok, :verified} -> :verified
                  {:error, {:key_hash_mismatch, _}} -> :key_hash_mismatch
                  {:error, {:value_hash_mismatch, _}} -> :value_hash_mismatch
                  {:error, {:root_hash_mismatch, _}} -> :root_hash_mismatch
                end
              tx
              |> Map.put_new(:verification, verification)
              |> Map.put_new(:proof, serialized_merkle_proof)
            end
            json(conn, Enum.map(proof, fn(tx) ->
                  %{tx |
                    from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize),
                    txs_hash: Serialization.hex_binary(tx.txs_hash, :serialize),
                    block_hash: Serialization.hex_binary(tx.block_hash, :serialize),
                    signature: Serialization.hex_binary(tx.signature, :serialize)
                   } end))

          _ ->
            json(conn, Enum.map(user_txs, fn(tx) ->
                  %{tx |
                    from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize),
                    txs_hash: Serialization.hex_binary(tx.txs_hash, :serialize),
                    block_hash: Serialization.hex_binary(tx.block_hash, :serialize),
                    signature: Serialization.hex_binary(tx.signature, :serialize)
                   } end))
        end
    end
  end

  defp build_tx_tree(txs) do
    if Enum.empty?(txs) do
      <<0::256>>
    else
      merkle_tree =
      for transaction <- txs do
        transaction_data_bin = :erlang.term_to_binary(transaction.data)
        {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
      end

      merkle_tree
      |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
      end)
    end
  end

  defp serialize_merkle_proof(proof, acc) when is_tuple(proof) do
    proof
    |> Tuple.to_list()
    |> serialize_merkle_proof(acc)
  end
  defp serialize_merkle_proof([], acc), do: acc
  defp serialize_merkle_proof([head | tail], acc) do
    if is_tuple(head) do
      serialize_merkle_proof(Tuple.to_list(head), acc)
    else
      acc = [Serialization.hex_binary(head, :serialize)| acc]
      serialize_merkle_proof(tail, acc)
    end
  end
end
