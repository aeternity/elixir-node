defmodule Aecore.Tx.Transaction do
  @moduledoc """
  Behaviour that states all the necessary functions that every custom transaction,
  child tx of DataTx should implement to work correctly on the blockchain
  """

  alias Aecore.Structures.SpendTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Chain.Chainstate

  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_types ::
          SpendTx.t()
          | OracleExtendTx.t()
          | OracleQueryTx.t()
          | OracleRegistrationTx.t()
          | OracleResponseTx.t()
          | NamePreClaimTx.t()
          | NameClaimTx.t()
          | NameUpdateTx.t()
          | NameTransferTx.t()
          | NameRevokeTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type tx_type_state() :: map()

  # Callbacks

  @doc "The name for state chain entry to be passed for processing"
  @callback get_chain_state_name() :: Chainstate.chain_state_types() | :none

  @callback init(payload()) :: tx_types()

  @callback validate(tx_types(), DataTx.t()) :: :ok | {:error, String.t()}

  @doc """
  Default function for executing a given transaction type.
  Make necessary changes to the account_state and tx_type_state of
  the transaction (Transaction type-specific chainstate)
  """
  @callback process_chainstate(
              Chainstate.accounts(),
              tx_type_state(),
              block_height :: non_neg_integer(),
              tx_types(),
              DataTx.t()
            ) :: {:ok, {Chainstate.accounts(), tx_type_state()}} | {:error, String.t()}

  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  ## Example
      def preprocess_check(tx, account_state, fee, nonce, %{} = tx_type_state) do
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
              Chainstate.accounts(),
              tx_type_state(),
              block_height :: non_neg_integer(),
              tx_types(),
              DataTx.t()
            ) :: :ok | {:error, reason}

  @callback deduct_fee(
              Chainstate.accounts(),
              non_neg_integer(),
              tx_types(),
              DataTx.t(),
              non_neg_integer()
            ) :: Chainstate.accounts()
end
