defmodule Aecore.Txs.Tx do
  @moduledoc """
  This module handles the txs : creation, verification
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData
  alias Aecore.Keys.Worker, as: Keys

  @doc """
  Takes the public key of the receiver and
  the value that will be sended. Returns signed tx

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - value: The amount of a transaction

  """
  @spec create(binary(), integer()) :: SignedTx.signed_tx()
  def create(to_acc, value) do
    {:ok, from_acc} = Keys.pubkey()
    {:ok, tx_data}  = create_tx_data(%{:from_acc => from_acc,
                                       :to_acc   => to_acc,
                                       :value    => value})
    {:ok, signature} = Keys.sign(tx_data)
    %SignedTx{data: tx_data, signature: signature}
  end

  @doc """
  Takes signed a transaction and then
  verify its signature against the public key

  """
  @spec verify(SignedTx.signed_tx()) :: boolean()
  def verify(%SignedTx{data: data, signature: signature}) do
    Keys.verify(data,signature,data.from_acc)
  end

  @spec create_tx_data(map()) :: {:ok, TxData.tx_data()}
  defp create_tx_data(%{from_acc: from_pubkey, to_acc: to_pubkey, value: value}) do
    nonce = Enum.random(0..1000000000000)
    {:ok, %{TxData.create |
            from_acc: from_pubkey,
            to_acc: to_pubkey,
            value: value,
            nonce: nonce}}
  end

end
