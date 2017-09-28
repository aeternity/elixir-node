defmodule Aecore.Tx do
  @moduledoc """
  This module handles the txs : creation, verification
  """

  alias Aecore.Structures.SignedTx

  @doc """
  Takes the public key of the receiver and
  the value that will be sended. Returns signed tx

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - value: The amount of a transaction

  """
  @spec create(binary(), integer()) :: SignedTx.signed_tx()
  def create(to_acc, value) do
    {:ok, from_acc}   = Aecore.Keys.Worker.pubkey()
    {:ok, coinbasetx} = Aecore.CoinBaseTx.new(%{:from_acc => from_acc,
                                                :to_acc   => to_acc,
                                                :value    => value})
    {:ok, signed_tx} = Aecore.Keys.Worker.sign(coinbasetx)
    signed_tx
  end

end
