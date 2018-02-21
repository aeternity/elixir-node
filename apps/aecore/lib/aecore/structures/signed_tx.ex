defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  """

  defstruct [:data, :signature]
  use ExConstructor

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization

  @type t :: %__MODULE__{
    data: DataTx.t(),
    signature: binary()
  }

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(tx) do
    tx.data.from_acc == nil && tx.signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(%SignedTx{data: data, signature: signature} = tx) do
    if Keys.verify_tx(tx) do
      case DataTx.is_valid(data) do
        :ok -> true
        {:error, _reason} -> false
      end
    end
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end



end
