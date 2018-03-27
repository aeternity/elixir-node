defmodule Aecore.Structures.Chainstate do
  @moduledoc """
  Aecore structure of a chainstate.
  """
  alias Aecore.Structures.Chainstate
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx

  require Logger

  @type tree :: tuple()

  @type t :: %Chainstate{
          accounts: tree()
        }

  defstruct [
    :accounts
  ]

  #  use ExConstructor

  @spec init() :: Chainstate.t()
  def init() do
    %Chainstate{
      :accounts => AccountStateTree.init_empty()
    }
  end

  @spec apply_transaction!(Chainstate.t(), SignedTx.t()) :: Chainstate.t()
  def apply_transaction!(chainstate, %SignedTx{data: data} = tx) do
    cond do
      SignedTx.is_coinbase?(tx) ->
        receiver_state = Account.get_account_state(chainstate.accounts, data.payload.receiver)

        new_receiver_state = SignedTx.reward(data, receiver_state)

        new_accounts_state =
          AccountStateTree.put(chainstate.accounts, data.payload.receiver, new_receiver_state)

        Map.put(chainstate, :accounts, new_accounts_state)

      data.sender != nil ->
        if SignedTx.is_valid?(tx) do
          DataTx.process_chainstate!(data, chainstate)
        else
          throw({:error, "Invalid transaction"})
        end

      true ->
        throw({:error, "Invalid transaction"})
    end
  end
end
