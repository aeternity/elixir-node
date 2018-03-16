defmodule Aehttpserver.Web.TxController do
  use Aehttpserver.Web, :controller
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization

  def show(conn, params) do
    account_bin =
      params["account"]
      |> Base.decode16!()

    user_txs = Pool.get_txs_for_address(account_bin)

    case user_txs do
      [] ->
        json(conn, [])

      _ ->
        case params["include_proof"] do
          "true" ->
            proof = Pool.add_proof_to_txs(user_txs)

            json(
              conn,
              Enum.map(proof, fn tx ->
                %{
                  tx
                  | from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize),
                    txs_hash: SignedTx.bech32_encode_root(tx.txs_hash),
                    block_hash: Header.bech32_encode(tx.block_hash),
                    signature: Serialization.base64_binary(tx.signature, :serialize),
                    proof: Serialization.merkle_proof(tx.proof, [])
                }
              end)
            )

          _ ->
            json(
              conn,
              Enum.map(user_txs, fn tx ->
                %{
                  tx
                  | from_acc: Serialization.hex_binary(tx.from_acc, :serialize),
                    to_acc: Serialization.hex_binary(tx.to_acc, :serialize),
                    txs_hash: SignedTx.bech32_encode_root(tx.txs_hash),
                    block_hash: Header.bech32_encode(tx.block_hash),
                    signature: Serialization.base64_binary(tx.signature, :serialize)
                }
              end)
            )
        end
    end
  end
end
