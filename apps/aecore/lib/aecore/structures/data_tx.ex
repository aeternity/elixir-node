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
    fee: non_neg_integer(),
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

  @spec create(atom(), map(), integer(), integer()) :: {:ok, DataTx.t()}
  def create(type, payload, fee, nonce) do
    {:ok, pubkey} = Keys.pubkey()
    tx_data =
      %DataTx{type: type,
              payload: payload,
              from_acc: pubkey,
              fee: fee,
              nonce: nonce}
    Keys.sign_tx(tx_data)
  end
end
