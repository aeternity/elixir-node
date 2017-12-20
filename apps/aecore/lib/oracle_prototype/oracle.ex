defmodule Aecore.OraclePrototype.Oracle do

  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  @spec register(map(), map(), binary(), integer()) :: :ok | :error
  def register(query_format, response_format, description, fee) do
    registration_tx_data =
      OracleRegistrationTxData.create(query_format, response_format,
                                      description, fee)
    Pool.add_transaction(sign_tx(registration_tx_data))
  end

  @spec query(binary(), any(), integer(), integer()) :: :ok | :error
  def query(oracle_hash, query_data, query_fee, response_fee) do
      case OracleQueryTxData.create(oracle_hash, query_data,
                                    query_fee, response_fee) do
        :error ->
          :error
        tx_data ->
          Pool.add_transaction(sign_tx(tx_data))
      end
  end

  @spec respond(binary(), any(), integer()) :: :ok | :error
  def respond(oracle_hash, response, fee) do
    case OracleResponseTxData.create(oracle_hash, response, fee) do
      :error ->
        :error
      tx_data ->
        Pool.add_transaction(sign_tx(tx_data))
    end
  end

  @spec sign_tx(map()) :: %SignedTx{}
  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end
end
