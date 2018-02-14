defmodule Aecore.OraclePrototype.Oracle do

  alias Aecore.Structures.OracleRegistrationSpendTx
  alias Aecore.Structures.OracleQuerySpendTx
  alias Aecore.Structures.OracleResponseSpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  also has a description field that gives string information about the oracle,
  an oracle uri is passed as the last argument which is mapped to the node's
  registered oracles, whenever a query references one of the node's registered
  oracles, the transaction is posted to the uri.
  """
  @spec register(map(), map(), binary(), integer(), String.t()) :: :ok | :error
  def register(query_format, response_format, description, fee, oracle_uri) do
    case OracleRegistrationSpendTx.create(query_format, response_format,
                                         description, fee) do
      :error ->
        :error
      tx_data ->
        signed_tx = sign_tx(tx_data)
        signed_tx_hash = :crypto.hash(:sha256, :erlang.term_to_binary(signed_tx))
        oracles_list = Application.get_env(:aecore, :operator)[:oracles]
        updated_oracles_map = Map.put(oracles_list, signed_tx_hash, oracle_uri)
        case Pool.add_transaction(signed_tx) do
          :ok ->
            Application.put_env(:aecore, :operator,
                                [is_node_operator: true,
                                 oracles: updated_oracles_map])
            :ok
          :error ->
            :error
        end
    end
  end

  @doc """
  Creates a query transaction with the given registered oracle hash, data query
  and a fee that is given to the oracle. It also has a fee field like every
  other transaction.
  """
  @spec query(binary(), any(), integer(), integer()) :: :ok | :error
  def query(oracle_hash, query_data, query_fee, response_fee) do
      case OracleQuerySpendTx.create(oracle_hash, query_data,
                                    query_fee, response_fee) do
        :error ->
          :error
        tx_data ->
          Pool.add_transaction(sign_tx(tx_data))
      end
  end

  @doc """
  Creates an oracle response transaction with the oracle referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), integer()) :: :ok | :error
  def respond(oracle_hash, response, fee) do
    case OracleResponseSpendTx.create(oracle_hash, response, fee) do
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
