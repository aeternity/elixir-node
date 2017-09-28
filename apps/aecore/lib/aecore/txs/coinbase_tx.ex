defmodule Aecore.CoinBaseTx do
  @moduledoc """
  Handles the coinbase transactions
  """

  alias Aecore.Structures.CoinBaseTx

  @doc """
  Creates a new coinbase transaction

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - from_acc: The public address of one account originating the transaction
     - value: The amount of a transaction
  """
  @spec new(map()) :: {:ok, CoinBaseTx.coinbase_tx()}
    def new(%{from_acc: from_pubkey, to_acc: to_pubkey, value: value}) do
      nonce = Enum.random(0..1000000000000)
      {:ok, %{CoinBaseTx.create |
              from_acc: from_pubkey,
              to_acc: to_pubkey,
              value: value,
              nonce: nonce}}
    end

  end
