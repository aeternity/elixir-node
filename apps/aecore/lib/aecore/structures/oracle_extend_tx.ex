defmodule Aecore.Structures.OracleExtendTx do
  @behaviour Aecore.Structures.Transaction

  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet

  @type payload :: %{
          ttl: non_neg_integer()
        }

  @type t :: %OracleExtendTx{
          ttl: non_neg_integer()
        }

  defstruct [:ttl]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name(), do: :oracles

  @spec init(payload()) :: OracleExtendTx.t()
  def init(%{ttl: ttl}) do
    %OracleExtendTx{ttl: ttl}
  end

  @spec validate(OracleExtendTx.t()) :: :ok | {:error, String.t()}
  def validate(%OracleExtendTx{ttl: ttl}) do
    if ttl > 0 do
      :ok
    else
      {:error, "#{__MODULE__}: Negative ttl in OracleExtendTx"}
    end
  end

  @spec process_chainstate(
          OracleExtendTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          ChainState.oracles()
        ) :: {ChainState.accounts(), ChainState.oracles()}
  def process_chainstate(
        %OracleExtendTx{} = tx,
        sender,
        fee,
        nonce,
        _block_height,
        accounts,
        oracle_state
      ) do
    new_sender_account_state =
      Map.get(accounts, sender, Account.empty())
      |> deduct_fee(fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = Map.put(accounts, sender, new_sender_account_state)

    updated_oracle_state =
      update_in(
        oracle_state,
        [:registered_oracles, sender, :tx, Access.key(:ttl), :ttl],
        &(&1 + tx.ttl)
      )

    {updated_accounts_chainstate, updated_oracle_state}
  end

  @spec preprocess_check(
          OracleExtendTx.t(),
          Wallet.pubkey(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          Oracle.registered_oracles()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _block_height, %{
        registered_oracles: registered_oracles
      }) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Map.has_key?(registered_oracles, sender) ->
        {:error, "#{__MODULE__}: Account isn't a registered operator"}

      fee < calculate_minimum_fee(tx.ttl) ->
        {:error, "#{__MODULE__}: Fee is too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
