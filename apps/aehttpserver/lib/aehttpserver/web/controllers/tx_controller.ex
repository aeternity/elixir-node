defmodule Aehttpserver.Web.TxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Serialization
  alias Aecore.Structures.Account

  def show(conn, params) do
    account_bin = Account.base58c_decode(params["account"])

    user_txs = Pool.get_txs_for_address(account_bin)

    case user_txs do
      [] ->
        json(conn, [])

      _ ->
        case params["include_proof"] do
          "true" ->
            proof = Pool.add_proof_to_txs(user_txs)

            json_info_with_proof =
              Map.put(Serialization.serialize_txs_info_to_json(user_txs), :proof, proof)

            json(
              conn,
              json_info_with_proof
            )

          _ ->
            json_info = Serialization.serialize_txs_info_to_json(user_txs)

            json(
              conn,
              json_info
            )
        end
    end
  end
end
