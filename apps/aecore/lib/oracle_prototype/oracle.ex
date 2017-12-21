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
    case OracleRegistrationTxData.create(query_format, response_format,
                                         description, fee) do
      :error ->
        :error
      tx_data ->
        signed_tx = sign_tx(tx_data)
        signed_tx_hash = :crypto.hash(:sha256, :erlang.term_to_binary(signed_tx))
        oracles_list = Application.get_env(:aecore, :operator)[:oracles_list]
        updated_oracles_list = Enum.uniq([oracles_list | signed_tx_hash])
        Application.put_env(:aecore, :operator, is_node_operator: true)
        Application.put_env(:aecore, :operator, oracles_list: updated_oracles_list)
        case Pool.add_transaction(signed_tx) do
          :ok ->
            Application.put_env(:aecore, :operator, is_node_operator: true)
            Application.put_env(:aecore, :operator,
                                oracles_list: updated_oracles_list)
            :ok
          :error ->
            :error
        end
    end
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
