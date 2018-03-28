defmodule Aecore.Structures.Transaction do
  @moduledoc """
  Behaviour that states all the necessary functions that every custom transaction,
  child tx of DataTx should implement to work correctly on the blockchain
  """

  alias Aecore.Structures.SpendTx
  alias Aecore.Naming.Structures.NamePreClaimTx
  alias Aecore.Naming.Structures.NameClaimTx
  alias Aecore.Naming.Structures.NameUpdateTx
  alias Aecore.Naming.Structures.NameRevokeTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet.Worker, as: Wallet

  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_types ::
          SpendTx.t()
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

  @callback init(payload()) :: tx_types()

  @callback is_valid?(tx_types()) :: boolean()

  @doc "The name for state chain entry to be passed for processing"
  @callback get_chain_state_name() :: Chainstate.chain_state_types()

  @doc """
  Default function for executing a given transaction type.
  Make necessary changes to the account_state and tx_type_state of
  the transaction (Transaction type-specific chainstate)
  """
  @callback process_chainstate!(
              tx_types(),
              Wallet.pubkey(),
              fee :: non_neg_integer(),
              nonce :: non_neg_integer(),
              block_height :: non_neg_integer(),
              Account.t(),
              tx_type_state()
            ) :: {Account.t(), tx_type_state()}

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
              tx_types(),
              ChainState.account(),
              Wallet.pubkey(),
              fee :: non_neg_integer(),
              nonce :: non_neg_integer(),
              block_height :: non_neg_integer(),
              tx_type_state :: map()
            ) :: :ok | {:error, reason}

  @callback deduct_fee(ChainState.account(), fee :: non_neg_integer()) :: ChainState.account()
end
