defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Contains the transaction structure for oracle registration
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias ExJsonSchema.Schema, as: JsonSchema
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

  @version 1

  @type payload :: %{
          query_format: Oracle.json_schema(),
          response_format: Oracle.json_schema(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl()
        }

  @type t :: %OracleRegistrationTx{
          query_format: map(),
          response_format: map(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl()
        }

  @type tx_type_state() :: Chainstate.oracles()

  defstruct [
    :query_format,
    :response_format,
    :query_fee,
    :ttl
  ]

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  use ExConstructor

  @spec init(payload()) :: t()
  def init(%{
        query_format: query_format,
        response_format: response_format,
        query_fee: query_fee,
        ttl: ttl
      }) do
    %OracleRegistrationTx{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %OracleRegistrationTx{
          query_format: query_format,
          response_format: response_format,
          ttl: ttl
        },
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    formats_valid =
      try do
        JsonSchema.resolve(query_format)
        JsonSchema.resolve(response_format)
        true
      rescue
        _ ->
          false
      end

    cond do
      ttl <= 0 ->
        {:error, "#{__MODULE__}: Invalid ttl"}

      !formats_valid ->
        {:error, "#{__MODULE__}: Invalid query or response format definition"}

      !Oracle.ttl_is_valid?(ttl) ->
        {:error, "#{__MODULE__}: Invald ttl"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleRegistrationTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    identified_oracle_owner = Identifier.create_identity(sender, :oracle)

    oracle = %Oracle{
      owner: identified_oracle_owner,
      query_format: tx.query_format,
      response_format: tx.response_format,
      query_fee: tx.query_fee,
      expires: Oracle.calculate_absolute_ttl(tx.ttl, block_height)
    }

    {:ok,
     {
       accounts,
       OracleStateTree.insert_oracle(oracles, oracle)
     }}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        oracles,
        block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx.ttl)}"}

      OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Account: #{inspect(sender)} is already an oracle"}

      !is_minimum_fee_met?(tx, fee, block_height) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    case tx.ttl do
      %{ttl: ttl, type: :relative} ->
        fee >= calculate_minimum_fee(ttl)

      %{ttl: ttl, type: :absolute} ->
        if block_height != nil do
          fee >=
            ttl
            |> Oracle.calculate_relative_ttl(block_height)
            |> calculate_minimum_fee()
        else
          true
        end
    end
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_registration_base_fee]

    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  def encode_to_list(%OracleRegistrationTx{} = tx, %DataTx{} = datatx) do
    ttl_type = Serialization.encode_ttl_type(tx.ttl)

    [
      @version,
      Identifier.serialize_identity(datatx.senders),
      datatx.nonce,
      "$æx" <> Serialization.transform_item(tx.query_format),
      "$æx" <> Serialization.transform_item(tx.response_format),
      tx.query_fee,
      ttl_type,
      tx.ttl.ttl,
      datatx.fee,
      datatx.ttl
    ]
  end

  def decode_from_list(@version, [
        encoded_senders,
        nonce,
        encoded_query_format,
        encoded_response_format,
        query_fee,
        encoded_ttl_type,
        ttl_value,
        fee,
        ttl
      ]) do
    ttl_type =
      encoded_ttl_type
      |> Serialization.transform_item(:int)
      |> Serialization.decode_ttl_type()

    query_format = Serialization.decode_format(encoded_query_format)

    response_format = Serialization.decode_format(encoded_response_format)

    payload = %{
      query_format: query_format,
      response_format: response_format,
      ttl: %{ttl: Serialization.transform_item(ttl_value, :int), type: ttl_type},
      query_fee: Serialization.transform_item(query_fee, :int)
    }

    with {:ok, senders} <- Identifier.deserialize_identity(encoded_senders) do
      {:ok,
       DataTx.init(
         OracleRegistrationTx,
         payload,
         senders,
         Serialization.transform_item(fee, :int),
         Serialization.transform_item(nonce, :int),
         Serialization.transform_item(ttl, :int)
       )}
    else
      {:eror, _} = error -> error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
