defmodule Aecore.Structures.Transaction do

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState

  @typedoc "Arbitrary structure data of a transaction"
  @type payload :: map()

  @typedoc "Structure of a custom transaction"
  @type tx_struct :: map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "ChainState structure"
  @type chain_state :: ChainState.t()

  # Callbacks

  @callback init(payload()) :: tx_type()
  @callback is_valid(tx_struct()) :: :ok | {:error, reason}
  @callback process_chain_state(tx_struct()) :: chain_state()

end
