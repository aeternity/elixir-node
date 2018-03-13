defmodule Aecore.Structures.Transaction do

  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet.Worker, as: Wallet

  @typedoc "Arbitrary map holding all the specific elements required
  by the specified transaction type"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_struct :: SpendTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type subdomain_cs() :: map()

  # Callbacks

  @callback init(payload()) :: tx_struct()

  @callback is_valid?(tx_struct()) :: boolean()

  @callback process_chainstate!(tx_struct(),
                                Wallet.pubkey(),
                                fee :: non_neg_integer(),
                                nonce :: non_neg_integer(),
                                block_height :: non_neg_integer(),
                                Account.t(),
                                subdomain_cs()) :: {Account.t(), subdomain_cs()}

  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  ## Example
      def preprocess_check(account_state, fee, nonce, block_height, %{} = subdomain_cs) do
        cond do
          account_state.balance - fee < 0 ->
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
  @callback preprocess_check(ChainState.account(),
                             fee :: non_neg_integer(),
                             nonce :: non_neg_integer(),
                             block_height :: non_neg_integer(),
                             subdomain_cs :: map()) :: :ok | {:error, reason}

  @callback deduct_fee(ChainState.account(),
                       fee :: non_neg_integer(),
                       nonce :: non_neg_integer()) :: ChainState.account()

end
