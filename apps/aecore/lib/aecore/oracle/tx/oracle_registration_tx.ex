defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Contains the transaction structure for oracle registration
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.Oracle
  alias ExJsonSchema.Schema, as: JsonSchema
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate

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
        %{registered_oracles: registered_oracles} = oracle_state,
        block_height,
        %OracleRegistrationTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    updated_registered_oracles =
      Map.put_new(registered_oracles, sender, %{
        owner: sender,
        query_format: tx.query_format,
        response_format: tx.response_format,
        query_fee: tx.query_fee,
        expires: Oracle.calculate_absolute_ttl(tx.ttl, block_height)
      })

    updated_oracle_state = %{
      oracle_state
      | registered_oracles: updated_registered_oracles
    }

    {:ok, {accounts, updated_oracle_state}}
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
        %{registered_oracles: registered_oracles},
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

      Map.has_key?(registered_oracles, sender) ->
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
end
