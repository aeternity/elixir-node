defmodule Aecore.Util.Serializable do
  @moduledoc """
  Module defining functions necessary for structure serialization
  """
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Aecore.Util.Serializable

      alias Aeutil.Serialization

      @spec rlp_encode(%__MODULE__{}) :: binary()
      def rlp_encode(%__MODULE__{} = structure) do
        Serialization.rlp_encode(structure)
      end

      @spec rlp_decode(binary()) :: {:ok, %__MODULE__{}} | {:error, String.t()}
      def rlp_decode(binary) do
        Serialization.rlp_decode_only(binary, __MODULE__)
      end

      defoverridable rlp_encode: 1, rlp_decode: 1
    end
  end

  @type error :: {:error, String.t()}

  # Callbacks
  @doc "Takes version and list from rlp encoding, returns decoded structure or error"
  @callback decode_from_list(integer(), list()) :: {:ok, map()} | error()

  @doc "Encodes structure to list for RLP encoding with version prepended but not tag"
  @callback encode_to_list(map()) :: list()
end
