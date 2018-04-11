defmodule Aecore.Structures.OracleRegistrationTx do
  alias __MODULE__
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Chainstate
  alias Aecore.Structures.AccountStateTree

  require Logger

  @type tx_type_state :: Chainstate.oracles()

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
  def get_chain_state_name(), do: :oracles

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

  @spec is_valid?(OracleRegistrationTx.t()) :: boolean()
  def is_valid?(%OracleRegistrationTx{
        query_format: query_format,
        response_format: response_format,
        ttl: ttl
      }) do
    formats_valid =
      try do
        ExJsonSchema.Schema.resolve(query_format)
        ExJsonSchema.Schema.resolve(response_format)
        true
      rescue
        e ->
          Logger.error("Invalid query or response format definition - " <> inspect(e))

          false
      end

    Oracle.ttl_is_valid?(ttl) && formats_valid
  end

  @spec process_chainstate!(
          OracleRegistrationTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Chainstate.account(),
          tx_type_state()
        ) :: {Chainstate.accounts(), tx_type_state()}
  def process_chainstate!(
        %OracleRegistrationTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        %{registered_oracles: registered_oracles} = oracle_state
      ) do
    preprocess_check!(
      tx,
      sender,
      Account.get_account_state(accounts, sender),
      fee,
      block_height,
      registered_oracles
    )

    new_sender_account_state =
      Account.get_account_state(accounts, sender)
      |> deduct_fee(fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_sender_account_state)

    updated_registered_oracles =
      Map.put_new(registered_oracles, sender, %{
        tx: tx,
        height_included: block_height
      })

    updated_oracle_state = %{
      oracle_state
      | registered_oracles: updated_registered_oracles
    }

    {updated_accounts_chainstate, updated_oracle_state}
  end

  @spec preprocess_check!(
          OracleRegistrationTx.t(),
          Wallet.pubkey(),
          Chainstate.account(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check!(tx, sender, account_state, fee, block_height, registered_oracles) do
    cond do
      account_state.balance - fee < 0 ->
        throw({:error, "Negative balance"})

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        throw({:error, "Invalid transaction TTL"})

      Map.has_key?(registered_oracles, sender) ->
        throw({:error, "Account is already an oracle"})

      !is_minimum_fee_met?(tx, fee, block_height) ->
        throw({:error, "Fee too low"})

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
