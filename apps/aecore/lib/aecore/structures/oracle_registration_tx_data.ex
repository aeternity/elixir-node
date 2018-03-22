defmodule Aecore.Structures.OracleRegistrationTxData do
  alias __MODULE__
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.ChainState
  alias Aeutil.Bits

  require Logger

  @type tx_type_state :: ChainState.oracles()

  @type payload :: %{
          query_format: map(),
          response_format: map(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl()
        }

  @type t :: %OracleRegistrationTxData{
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

  @spec init(payload()) :: OracleRegistrationTxData.t()
  def init(%{
        query_format: query_format,
        response_format: response_format,
        query_fee: query_fee,
        ttl: ttl
      }) do
    %OracleRegistrationTxData{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }
  end

  @spec is_valid?(OracleRegistrationTxData.t()) :: boolean()
  def is_valid?(%OracleRegistrationTxData{
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
          Logger.error("Invalid query or response format definition; " <> e)

          false
      end

    Oracle.ttl_is_valid?(ttl) && formats_valid
  end

  @spec process_chainstate!(
          OracleRegistrationTxData.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %OracleRegistrationTxData{} = tx,
        from_acc,
        fee,
        nonce,
        block_height,
        accounts,
        %{registered_oracles: registered_oracles} = oracle_state
      ) do
    case preprocess_check(
           tx,
           from_acc,
           Map.get(accounts, from_acc, Account.empty()),
           fee,
           nonce,
           block_height,
           registered_oracles
         ) do
      :ok ->
        new_from_account_state =
          Map.get(accounts, from_acc, Account.empty())
          |> deduct_fee(fee)

        updated_accounts_chainstate = Map.put(accounts, from_acc, new_from_account_state)

        updated_registered_oracles =
          Map.put_new(registered_oracles, from_acc, %{
            tx: tx,
            height_included: block_height
          })

        updated_oracle_state = %{
          oracle_state
          | registered_oracles: updated_registered_oracles
        }

        {updated_accounts_chainstate, updated_oracle_state}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @spec preprocess_check(
          OracleRegistrationTxData.t(),
          Wallet.pubkey(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, from_acc, account_state, fee, nonce, block_height, registered_oracles) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "Invalid transaction TTL"}

      Map.has_key?(registered_oracles, from_acc) ->
        {:error, "Account is already an oracle"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t(), integer()) :: boolean()
  def is_minimum_fee_met?(tx, block_height) do
    case tx.data.payload.ttl do
      %{ttl: ttl, type: :relative} ->
        tx.data.fee >= calculate_minimum_fee(ttl)

      %{ttl: ttl, type: :absolute} ->
        if block_height != nil do
          tx.data.fee >=
            ttl
            |> Oracle.calculate_relative_ttl(block_height)
            |> calculate_minimum_fee()
        else
          true
        end
    end
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("or", bin)
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_registration_base_fee]

    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
