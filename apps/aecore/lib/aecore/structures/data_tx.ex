defmodule  Aecore.Structures.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Keys.Worker, as: Keys

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the main transaction wrapper"
  @type t :: %__MODULE__{
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

  @spec init(atom(), map(), binary(), integer(), integer()) :: {:ok, DataTx.t()}
  def init(type, payload, from_acc, fee, nonce) do
    {:ok,  %__MODULE__{type: type,
                       payload: type.init(payload),
                       from_acc: from_acc,
                       fee: fee,
                       nonce: nonce}}
  end

  @spec is_valid(DataTx.t()) :: :ok | {:error, reason()}
  def is_valid(%__MODULE__{type: type, payload: payload, fee: fee}) do
    if fee >= 0 do
      type.is_valid(payload)
    else
      {:error, "Fee not enough"}
    end
  end

  def process_chainstate(%__MODULE__{type: type, payload: payload} = tx,
                         account_state, block_height) do

    type.process_chainstate(payload, tx.from_acc, tx.fee, tx.nonce, account_state, block_height)
  end

end
