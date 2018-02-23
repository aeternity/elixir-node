defmodule Aecore.Structures.Transaction do

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState

  @typedoc "Arbitrary structure data of a transaction"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_struct :: map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "The public key of the account"
  @type pub_key :: binary()

  @typedoc "Structure that holds the account info"
  @type account_state :: %{pub_key() => %{balance: integer(),
                                         locked: [%{amount: integer(), block: integer()}],
                                         nonce: integer()}}

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type subdomain_chainstate() :: map()

  # Callbacks

  @callback init(payload()) :: tx_struct()

  @callback is_valid(tx_struct()) :: :ok | {:error, reason}

  @callback process_chainstate!(tx_struct(),
                                pub_key(),
                                fee :: non_neg_integer(),
                                nonce :: non_neg_integer(),
                                block_height :: non_neg_integer(),
                                account_state(),
                                subdomain_chainstate()) :: account_state()


  @doc """
  Default preprocess_check implementation for deduction of the fee.
  You may add as many as you need additional checks
  depending on your transaction specifications.

  ## Example
      def preprocess_check(account_state, fee, nonce, block_height, %{} = subdomain_chainstate) do
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
  @callback preprocess_check(account_state(),
                             fee :: non_neg_integer(),
                             nonce :: non_neg_integer(),
                             block_height :: non_neg_integer(),
                             additional_variables :: map()) :: :ok | {:error, reason}

  @callback deduct_fee(account_state(),
                       fee :: non_neg_integer(),
                       nonce :: non_neg_integer()) :: account_state()

end
