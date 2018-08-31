defmodule Aecore.Chain.Identifier do
  @moduledoc """
  Utility module for interacting with identifiers.

  Our binaries like account pubkey or hashes will already be represented as encoded (with already specified tag) binaries, following  the next formula:
   <<Tag:1/unsigned-integer-unit:8, Binary:32/binary-unit:8>>, Where
   Tag - is  a non-negative integer , a number from a range of 1..6 (at the current state of this documentation, for more info get in config.exs file and find :aecore, :binary_ids list),
   Binary - is a regular binary , which byte size is 32 bytes.
  Example:
  Epoch has a separate structure for id's:
  %Identifier{tag: atom(), value: value() }
  Account structure:

   In Epoch's erlang core implementation (as it would look like the following Elixir code):
   %Account{
    pubkey: %Identifier{tag: :account, value: <<"some_pub_key">>},
    nonce: non_neg_integer(),
    balance: non_neg_integer()
  }
  """

  alias __MODULE__
  defstruct type: :undefined, value: ""
  use ExConstructor

  @type t() :: %Identifier{type: type(), value: value()}
  @type type() :: :account | :name | :commitment | :oracle | :contract | :channel
  @type value() :: binary()

  # Use the binary size as guard for correct value size
  # This requires special look over the code
  # @bdata_size 32
  @tag_size 8

  @spec create_identity(type(), value()) :: Identifier.t()
  # byte_size(data) == @data_size data should be stricted to 32 bytes only
  def create_identity(value, type)
      when is_atom(type) and is_binary(value) do
    %Identifier{type: type, value: value}
  end

  def check_identity(%Identifier{} = id, type) do
    case create_identity(id.value, type) do
      {:ok, check_id} -> check_id == id
      {:error, msg} -> {:error, msg}
    end
  end

  def check_identity(_, _) do
    {:error, "#{__MODULE__}: Invalid ID"}
  end

  # ==============API needed for RLP===============
  # byte_size(data.value) == 32 # data should be stricted to 32 bytes only
  @spec encode_to_binary(Identifier.t()) :: binary()
  def encode_to_binary(%Identifier{} = data) do
    tag = type_to_tag(data.type)
    <<tag::unsigned-integer-size(@tag_size), data.value::binary>>
  end

  # byte_size(data) == @data_size # data should be stricted to 32 bytes only
  @spec decode_from_binary(binary()) :: tuple() | {:error, String.t()}
  def decode_from_binary(<<tag::unsigned-integer-size(@tag_size), data::binary>>)
      when is_binary(data) do
    case tag_to_type(tag) do
      {:error, msg} ->
        {:error, msg}

      {:ok, type} ->
        {:ok, %Identifier{type: type, value: data}}
    end
  end

  @spec encode_list_to_binary(list(Identifier.t())) :: list(binary())
  def encode_list_to_binary([]), do: []

  def encode_list_to_binary([head | rest]) do
    [encode_to_binary(head) | encode_list_to_binary(rest)]
  end

  @spec decode_list_from_binary(list(binary())) ::
          {:ok, list(Identifier.t())} | {:error, String.t()}
  def decode_list_from_binary([]), do: {:ok, []}

  def decode_list_from_binary([head | rest]) do
    with {:ok, head_decoded} <- decode_from_binary(head),
         {:ok, rest_decoded} <- decode_list_from_binary(rest) do
      {:ok, [head_decoded | rest_decoded]}
    else
      {:error, _} = error -> error
    end
  end

  defp type_to_tag(:account), do: 1
  defp type_to_tag(:name), do: 2
  defp type_to_tag(:commitment), do: 3
  defp type_to_tag(:oracle), do: 4
  defp type_to_tag(:contract), do: 5
  defp type_to_tag(:channel), do: 6

  defp tag_to_type(1), do: {:ok, :account}
  defp tag_to_type(2), do: {:ok, :name}
  defp tag_to_type(3), do: {:ok, :commitment}
  defp tag_to_type(4), do: {:ok, :oracle}
  defp tag_to_type(5), do: {:ok, :contract}
  defp tag_to_type(6), do: {:ok, :channel}
  defp tag_to_type(_), do: {:error, "#{__MODULE__}: Invalid tag"}
end
