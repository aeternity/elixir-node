defmodule Aecore.Structures.CoinbaseTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction
  alias Aecore.Structures.CoinbaseTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet
  alias Aecore.Structures.Account

  require Logger

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          to_acc: Wallet.pubkey(),
          value: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Coinbase Transaction type"
  @type t :: %CoinbaseTx{
          to_acc: Wallet.pubkey(),
          value: non_neg_integer()
        }

  @doc """
  Definition of Aecore CoinbaseTx structure

  ## Parameters
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of tokens send through the transaction
  """
  defstruct [:to_acc, :value]
  use ExConstructor

  # Callbacks
  
  def get_chain_state_name() do nil end

  @spec init(payload()) :: CoinbaseTx.t()
  def init(%{to_acc: to_acc, value: value} = _payload) do
    %CoinbaseTx{to_acc: to_acc, value: value}
  end

  @doc """
  Creates a rewarding CoinbaseTx for the miner that mined the block
  """
  @spec create(binary(), integer()) :: payload()
  def create(to_acc, value) do
    %CoinbaseTx{to_acc: to_acc, value: value}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec is_valid?(CoinbaseTx.t(), SignedTx.t()) :: boolean()
  def is_valid?(%CoinbaseTx{value: value}, signed_tx) do
    data_tx = SignedTx.data_tx(signed_tx)

    cond do
      value < 0 ->
        Logger.error("Value cannot be a negative number")
        false

      DataTx.fee(data_tx) != 0 ->
        Logger.error("Fee has to be 0")
        false

      length(DataTx.senders(data_tx)) != 0 ->
        Logger.error("Invalid senders size")
        false

      true ->
        true
    end
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          SignedTx.t()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(accounts, %{}, _block_height, %CoinbaseTx{} = tx, _signed_tx) do
    new_accounts_state =
      accounts
      |> Map.update(tx.to_acc, Account.empty(), fn acc ->
        Account.transaction_in(acc, tx.value)
      end)

    {new_accounts_state, %{}}   
  end

  def process_chainstate!(_accounts, %{}, _block_height, _tx, _signed_tx) do
    throw({:error, "Invalid coinbase tx"})
  end

  @doc """
  Checks whether all the data is valid according to the CoinbaseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          SignedTx.t()
        ) :: :ok
  def preprocess_check!(_accounts, %{}, _block_height, _tx, _signed_tx) do
    :ok
  end

  @spec deduct_fee(ChainState.accounts(), CoinbaseTx.t(), SignedTx.t(), non_neg_integer()) :: ChainState.accounts()
  def deduct_fee(accounts, _tx, _signed_tx, _fee) do
    accounts
  end
end
