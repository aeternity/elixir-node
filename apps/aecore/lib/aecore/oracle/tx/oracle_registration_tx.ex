defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Contains the transaction structure for oracle registration
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Oracle.Oracle
  alias ExJsonSchema.Schema, as: JsonSchema
  alias Aecore.Account.AccountStateTree
  alias Aecore.Oracle.OracleStateTree

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

  @spec validate(OracleRegistrationTx.t()) :: :ok | {:error, String.t()}
  def validate(%OracleRegistrationTx{
        query_format: query_format,
        response_format: response_format,
        ttl: ttl
      }) do
    formats_valid =
      try do
        JsonSchema.resolve(query_format)
        JsonSchema.resolve(response_format)
        :ok
      rescue
        e ->
          {:error, "#{__MODULE__}: Invalid query or response format definition - #{inspect(e)}"}
      end

    Oracle.ttl_is_valid?(ttl) && formats_valid
  end

  @spec process_chainstate(
          OracleRegistrationTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.tree(),
          OracleStateTree.oracle_state()
        ) :: {AccountStateTree.tree(), Oracle.t()}
  def process_chainstate(
        %OracleRegistrationTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        registered_oracles
      ) do
    new_sender_account_state =
      accounts
      |> Account.get_account_state(sender)
      |> deduct_fee(fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_sender_account_state)

    updated_oracle_chainstate =
      OracleStateTree.put_registered_oracles(registered_oracles, %{
        sender => %{
          tx: tx,
          height_included: block_height
        }
      })

    {updated_accounts_chainstate, updated_oracle_chainstate}
  end

  @spec preprocess_check(
          OracleRegistrationTx.t(),
          Wallet.pubkey(),
          Account.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          OracleStateTree.oracle_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _nonce, block_height, registered_oracles) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance)}"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx.ttl)}"}

      OracleStateTree.has_key?(registered_oracles, sender) ->
        {:error, "#{__MODULE__}: Account: #{inspect(sender)} is already an oracle"}

      !is_minimum_fee_met?(tx, fee, block_height) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(Account.t(), non_neg_integer()) :: Account.t()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
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
