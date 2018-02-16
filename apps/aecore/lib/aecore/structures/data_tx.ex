defmodule  Aecore.Structures.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.DataTx
  alias Aecore.Keys.Worker, as: Keys
   @type t :: %DataTx{
    type: atom(),
    payload: any(),
    from_acc: binary(),
    fee: integer(),
    nonce: non_neg_integer()
   }

  @doc """
  Definition of Aecore DataT structure

  ## Parameters
  - type: To account is the public address of the account receiving the transaction
  - payload:
  - from_acc: From account is the public address of one account originating the transaction
  - fee: The amount of a transaction
  - nonce: A random integer generated on initialisation of a transaction.Must be unique

  """
  defstruct [:type, :payload, :from_acc , :fee, :nonce]
  use ExConstructor

#  @spec create(binary(), binary(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: {:ok, DataTx.t()}
  def create(type, payload, from_acc, fee, nonce) do
     tx_data =
       %DataTx{type: type,
               payload: payload,
               from_acc: from_acc,
               fee: fee,
               nonce: nonce}
    Keys.sign_tx(tx_data)
  end

  @spec hash_tx(DataTx.t()) :: binary()
  def hash_tx(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
  end

end
