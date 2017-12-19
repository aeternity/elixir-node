defmodule Aecore.OraclePrototype.Oracle do

  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  def register(query_format, response_format, description, fee) do
    registration_tx_data =
      OracleRegistrationTxData.create(query_format, response_format,
                                      description, fee)
    Pool.add_transaction(sign_tx(registration_tx_data))
  end

  def query(oracle_hash, query_data, query_fee, response_fee) do
      case OracleQueryTxData.create(oracle_hash, query_data,
                                    query_fee, response_fee) do
        {:error, message} ->
          Logger.error(message)
          :error
        tx_data ->
          Pool.add_transaction(sign_tx(tx_data))
      end
  end

  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end
end
