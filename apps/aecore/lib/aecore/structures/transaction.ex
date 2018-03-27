defmodule Aecore.Structures.Transaction do
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.CoinbaseTx
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet.Worker, as: Wallet

  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_types :: SpendTx.t() | CoinbaseTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type tx_type_state() :: map()

  # Callbacks

  @callback init(payload()) :: tx_types()

  @callback is_valid?(tx_types(), list(binary()), fee :: integer()) :: boolean()

  @doc """
  Default function for executing a given transaction type.
  Make necessary changes to the account_state and tx_type_state of
  the transaction (Transaction type-specific chainstate)
  """
  @callback process_chainstate!(
              ChainState.chainstate(),
              tx_types(),
              list(Wallet.pubkey()),
              fee :: non_neg_integer()
            ) :: ChainState.chainstate()

  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  ## Example
      def preprocess_check(tx, account_state, fee, nonce, %{} = tx_type_state) do
        cond do
          account_state.balance - (tx.value + fee) < 0 ->
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
              ChainState.chainstate(),
              list(Wallet.pubkey()),
              fee :: non_neg_integer()
            ) :: :ok | {:error, reason}

  @callback deduct_fee(
              ChainState.chainstate(),
              tx_types(),
              from_accs :: list(binary()),
              fee :: non_neg_integer()
            ) :: ChainState.account()
end
