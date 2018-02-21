defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aeutil.Serialization

  @typedoc "Arbitrary structure data of a transaction"
  @type payload ::map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %__MODULE__{
    to_acc: binary(),
    value: non_neg_integer(),
    lock_time_block: non_neg_integer()
  }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of a transaction
  """
  defstruct [:to_acc, :value, :lock_time_block]
  use ExConstructor

  @spec init(payload()) :: SpendTx.t()
  def init(%{to_acc: to_acc, value: value, lock_time_block: lock} = payload) do
    %__MODULE__{to_acc: to_acc,
             value: value,
             lock_time_block: lock}
  end

  @spec is_valid(SpendTx.t()) :: :ok | {:error, reason()}
  def is_valid(%__MODULE__{value: value}) do
    if value >= 0 do
      :ok
    else
      {:error, "Value not enough"}
    end
  end

  @spec
  def process_chain_state() do

  end

end
