defmodule Aecore.Tx.Transaction do
  @moduledoc """
  Behaviour that states all the necessary functions that every custom transaction,
  child tx of DataTx should implement to work correctly on the blockchain
  """

  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account

  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_types :: SpendTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type tx_type_state() :: map()

  # Callbacks

  @callback get_chain_state_name() :: atom() | nil

  @callback init(payload()) :: tx_types()

  @callback validate(tx_types()) :: :ok | {:error, String.t()}

  @doc """
  Default function for executing a given transaction type.
  Make necessary changes to the account_state and tx_type_state of
  the transaction (Transaction type-specific chainstate)
  """
  @callback process_chainstate(
              tx_types(),
              DataTx.t(),
              block_height :: non_neg_integer(),
              ChainState.account(),
              tx_type_state()
            ) :: {Account.t(), tx_type_state()}

  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  ## Example
      def preprocess_check!(tx, account_state, fee, nonce, %{} = tx_type_state) do
        cond do
          account_state.balance - (tx.amount + fee) < 0 ->
           {:error, "Negative balance"}

        account_state.nonce >= nonce ->
           {:error, "Nonce too small"}

        1-st_additional_check_required_by_your_tx_functionality ->
          {:error, reason}

        . . .

        n-th_additional_checks_required_by_your_tx_functionality ->
           {:error, reason}

          true ->
           :ok
      end
  """
  @callback preprocess_check(
              ChainState.accounts(),
              tx_type_state(),
              block_height :: non_neg_integer(),
              SpendTx.t(),
              tx_types()
            ) :: :ok | {:error, reason}

  @callback deduct_fee(
              ChainState.accounts(),
              non_neg_integer(),
              tx_types(),
              DataTx.t(),
              non_neg_integer()
            ) :: ChainState.account()
end
