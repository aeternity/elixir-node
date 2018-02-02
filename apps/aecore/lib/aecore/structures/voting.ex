defmodule Aecore.Structures.Voting do
  @moduledoc """
  Aecore structure of a transaction data.
  """
  alias Aecore.Structures.TxData
  alias Aecore.Structures.Voting

  @type t :: %Voting{
  }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  - locked: %{amount: non_neq_integer(), block: non_neq_integer()} map with amount of tokens and block when they will go to balance
  """
  defstruct []
  use ExConstructor

  @spec empty() :: t()
  def empty() do
    %Voting{}
  end
  
  @spec transaction_in!(Voting.t(), TxData.t(), integer()) :: Voting.t()
  def transaction_in!(voting, tx, block_height) do
    voting
  end
end
