defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  @type signed_tx() :: %SignedTx{}

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase(signed_tx()) :: boolean()
  def is_coinbase(%{data: %{from_acc: key}, signature: signature}) do
    key == nil && signature == nil
  end

  @spec is_valid(signed_tx()) :: boolean()
  def is_valid(%{data: data, signature: signature}) do
    data.value >= 0 &&
      Aewallet.Signing.verify(:erlang.term_to_binary(data), signature, data.from_acc)
  end

  @doc """
  Takes the public key of the receiver and
  the value that will be sended. Returns signed tx

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - value: The amount of a transaction

  """
  @spec sign_tx(binary(), integer(), integer(), integer(), integer()) :: {:ok, %SignedTx{}}
  def sign_tx(to_acc, value, nonce, fee, lock_time_block \\ 0) do
    path = Path.join(aewallet_path(), "wallet--2018-1-9-15-32-15")
    wallet_pass = "1234"
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(path, wallet_pass)
    {:ok, tx_data} = TxData.create(from_acc, to_acc, value, nonce, fee, lock_time_block)
    {:ok, priv_key} = Aewallet.Wallet.get_private_key(path, wallet_pass)

    signature = Aewallet.Signing.sign(:erlang.term_to_binary(tx_data), priv_key)
    signed_tx = %SignedTx{data: tx_data, signature: signature}
    {:ok, signed_tx}
  end

  defp aewallet_path(), do: Application.get_env(:aecore, :aewallet)[:path]
end
