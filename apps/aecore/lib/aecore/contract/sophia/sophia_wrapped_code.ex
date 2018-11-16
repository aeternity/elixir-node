defmodule Aecore.Contract.Sophia.SophiaWrappedCode do
  @moduledoc """
  Module, defining the wrapped Sophia code structure
  """

  alias __MODULE__

  @version 1

  @type t :: %SophiaWrappedCode{
          source_hash: binary(),
          # [type_hash, name, arg_type, out_type]
          type_info: map(),
          byte_code: binary()
        }

  defstruct [:source_hash, :type_info, :byte_code]

  use Aecore.Util.Serializable

  @spec encode_to_list(SophiaWrappedCode.t()) :: list()
  def encode_to_list(%SophiaWrappedCode{
        source_hash: source_hash,
        type_info: type_info,
        byte_code: byte_code
      }) do
    [@version, source_hash, type_info, byte_code]
  end

  @spec decode_from_list(binary(), atom()) :: term() | {:error, binary()}
  def decode_from_list(@version, [source_hash, type_info, byte_code]) do
    {:ok,
     %SophiaWrappedCode{
       source_hash: source_hash,
       type_info: type_info,
       byte_code: byte_code
     }}
  end
end
