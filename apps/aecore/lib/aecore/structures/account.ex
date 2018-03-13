defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger
  alias Aecore.Structures.Account

  @type t :: %Account{
    balance: non_neg_integer(),
    nonce: non_neg_integer()
  }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  """
  defstruct [:balance, :nonce]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0,
             nonce: 0}
  end

end
