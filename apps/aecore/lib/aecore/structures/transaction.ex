defmodule Aecore.Structures.Transaction do

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState

  @typedoc "Arbitrary structure data of a transaction"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_struct :: map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds the account info"
  @type account_state :: map()

  @typedoc "The public key of the account"
  @type pub_key :: binary()

  # Callbacks

  @callback init(payload()) :: tx_type()

  @callback is_valid(tx_struct()) :: :ok | {:error, reason}

  @callback deduct_fee(account_state(),
                       fee :: non_neg_integer(),
                       nonce :: non_neg_integer()) :: :ok | {:error, reason}

  @callback process_chainstate!(tx_struct(),
                                pub_key(),
                                fee :: non_neg_integer(),
                                nonce :: non_neg_integer(),
                                account_state(),
                                block_height :: non_neg_integer()) :: account_state()

end
