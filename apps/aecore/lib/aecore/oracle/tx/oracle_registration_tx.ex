defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Contains the transaction structure for oracle registration
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Chain.Chainstate
  alias ExJsonSchema.Schema, as: JsonSchema
  alias Aecore.Account.AccountStateTree

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

  defstruct [
    :query_format,
    :response_format,
    :query_fee,
    :ttl
  ]

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  use ExConstructor

  @spec init(payload()) :: OracleRegistrationTx.t()
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

  @spec validate(OracleRegistrationTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
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
          Chainstate.oracles(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), Chainstate.oracles()}}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleRegistrationTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    updated_oracle_chainstate =
      OracleStateTree.put_new_registered_oracle(oracles, sender, %{
        owner: sender,
        query_format: tx.query_format,
        response_format: tx.response_format,
        query_fee: tx.query_fee,
        expires: Oracle.calculate_absolute_ttl(tx.ttl, block_height)
      })

    {:ok, {accounts, updated_oracle_chainstate}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          Chainstate.oracles(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
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

      OracleStateTree.has_key?(oracles, sender) ->
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
          OracleExtendTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: ChainState.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(OracleRegistrationTx.t(), non_neg_integer(), non_neg_integer()) ::
          boolean()
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
