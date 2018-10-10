defmodule Aecore.Tx.Transaction do
  @moduledoc """
  Behaviour that states all the necessary functions that every custom transaction,
  child tx of DataTx should implement to work correctly on the blockchain
  """

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Aecore.Tx.Transaction

      @spec chainstate_senders?() :: boolean()
      def chainstate_senders?() do
        false
      end

      defoverridable chainstate_senders?: 0
    end
  end

  alias Aecore.Tx.DataTx
  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_types ::
          Aecore.Account.Tx.SpendTx.t()
          | Aecore.Oracle.Tx.OracleExtendTx.t()
          | Aecore.Oracle.Tx.OracleRegistrationTx.t()
          | Aecore.Oracle.Tx.OracleResponseTx.t()
          | Aecore.Oracle.Tx.OracleResponseTx.t()
          | Aecore.Naming.Tx.NamePreClaimTx.t()
          | Aecore.Naming.Tx.NameClaimTx.t()
          | Aecore.Naming.Tx.NameUpdateTx.t()
          | Aecore.Naming.Tx.NameTransferTx.t()
          | Aecore.Naming.Tx.NameRevokeTx.t()
          | Aecore.Channel.Tx.ChannelCreateTx.t()
          | Aecore.Channel.Tx.ChannelCloseMutalTx.t()
          | Aecore.Channel.Tx.ChannelCloseSoloTx.t()
          | Aecore.Channel.Tx.ChannelSlashTx.t()
          | Aecore.Channel.Tx.ChannelSettleTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type tx_type_state() :: map()

  # Callbacks

  @doc "The name for state chain entry to be passed for processing"
  @callback get_chain_state_name() :: Chainstate.chain_state_types()

  @callback init(payload()) :: tx_types()

  @callback validate(tx_types(), DataTx.t()) :: :ok | {:error, reason()}

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
            ) :: {:ok, {Chainstate.accounts(), tx_type_state()}} | {:error, reason()}

  @doc """
  Default function for checking if the minimum fee is met for all transaction types.
  """
  @callback is_minimum_fee_met?(
              DataTx.t(),
              tx_type_state(),
              block_height :: non_neg_integer()
            ) :: boolean()

  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  # Example
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
