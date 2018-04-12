defmodule Aecore.Structures.OracleExtendTx do
  
  @behaviour Aecore.Structures.Transaction

  alias __MODULE__
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Account

  require Logger
  
  @type tx_type_state :: ChainState.oracles()

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

  @spec is_valid?(OracleExtendTx.t(), SignedTx.t()) :: boolean()
  def is_valid?(%OracleExtendTx{ttl: ttl}, signed_tx) do
    senders = signed_tx |> SignedTx.data_tx() |> DataTx.senders()

    cond do
      ttl <= 0 ->
        Logger.error("Invalid ttl")
        false

      length(senders) != 1 ->
        Logger.error("Invalid senders number")
        false

      true ->
        true
    end
  end
  
  @spec process_chainstate!(
          ChainState.account(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleExtendTx.t(),
          SignedTx.t()
  ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate!(
        accounts,
        oracle_state,
        _block_height,
        %OracleExtendTx{} = tx,
        signed_tx
  ) do
    sender = signed_tx |> SignedTx.data_tx() |> DataTx.sender()

    updated_oracle_state =
      update_in(
        oracle_state,
        [:registered_oracles, sender, :tx, Access.key(:ttl), :ttl],
        &(&1 + tx.ttl)
      )

    {accounts, updated_oracle_state}
  end
  
  @spec preprocess_check!(
    ChainState.accounts(),
    Oracle.oracles(),
    non_neg_integer(),
    OracleExtendTx.t(),
    SignedTx.t()
  ) :: :ok
  def preprocess_check!(accounts,
                        %{registered_oracles: registered_oracles},
                        _block_height, 
                        tx, 
                        signed_tx) do
    data_tx = SignedTx.data_tx(signed_tx)
    sender = DataTx.sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      Map.get(accounts, sender, Account.empty()).balance - fee < 0 ->
        throw({:error, "Negative balance"})

      !Map.has_key?(registered_oracles, sender) ->
        throw({:error, "Account isn't a registered operator"})

      fee < calculate_minimum_fee(tx.ttl) ->
        throw({:error, "Fee is too low"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.accounts(), OracleExtendTx.t(), SignedTx.t(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(accounts, _tx, signed_tx, fee) do
    DataTx.standard_deduct_fee(accounts, signed_tx, fee)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
