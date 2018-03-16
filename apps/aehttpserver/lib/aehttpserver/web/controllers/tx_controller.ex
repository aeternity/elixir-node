defmodule Aehttpserver.Web.TxController do
  use Aehttpserver.Web, :controller
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization
  alias Aecore.Structures.Account
  alias Aeutil.Bits

  def show(conn, params) do
    account_bin = Bits.decode58(params["account"])

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
                  | from_acc: Account.base58_encode(tx.from_acc),
                    to_acc: Account.base58_encode(tx.to_acc),
                    txs_hash: SignedTx.base58_encode_root(tx.txs_hash),
                    block_hash: Header.base58_encode(tx.block_hash),
                    signature: Base.encode64(tx.signature),
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
                  | from_acc: Account.base58_encode(tx.from_acc),
                    to_acc: Account.base58_encode(tx.to_acc),
                    txs_hash: SignedTx.base58_encode(tx.txs_hash),
                    block_hash: Header.base58_encode(tx.block_hash),
                    signature: Base.encode64(tx.signature)
                }
              end)
            )
        end
    end
  end
end
