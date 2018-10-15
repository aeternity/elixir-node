defmodule Aecore.Chain.Identifier do
  @moduledoc """
  Utility module for interacting with identifiers.

  Our binaries like account pubkey or hashes will already be represented as encoded (with already specified tag) binaries, using the following format:
   <<Tag:1/unsigned-integer-unit:8, Binary:32/binary-unit:8>>,
   Where Tag is a non-negative integer ranging from 1 to 6 (at the current state of this documentation, for more info - :aecore, :binary_ids list in config.exs)
   and Binary is a regular 32 byte binary
  """

  alias __MODULE__
  defstruct type: :undefined, value: ""

  @typedoc "Structure of the Identifier Transaction type"
  @type t() :: %Identifier{type: type(), value: value()}

  @type type() :: :account | :name | :commitment | :oracle | :contract | :channel
  @type value() :: binary()

  @tag_size 8

  @spec create_identity(value(), type()) :: Identifier.t()
  def create_identity(value, type)
      when is_atom(type) and is_binary(value) do
    %Identifier{type: type, value: value}
  end

  @spec create_encoded_to_binary(type(), value()) :: binary()
  def create_encoded_to_binary(value, type) do
    value
    |> create_identity(type)
    |> encode_to_binary()
  end

  @spec check_identity(Identifier.t(), value()) :: {:ok, value} | {:error, String.t()}
  def check_identity(%Identifier{value: value} = id, type) do
    case create_identity(value, type) do
      {:ok, check_id} -> check_id == id
      {:error, msg} -> {:error, msg}
    end
  end

  def check_identity(_, _) do
    {:error, "#{__MODULE__}: Invalid ID"}
  end

  # API needed for RLP
  @spec encode_to_binary(Identifier.t()) :: binary()
  def encode_to_binary(%Identifier{value: value, type: type}) do
    tag = type_to_tag(type)
    <<tag::unsigned-integer-size(@tag_size), value::binary>>
  end

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

  @spec decode_from_binary_to_value(binary(), type()) :: value() | {:error, String.t()}
  def decode_from_binary_to_value(data, type) do
    case decode_from_binary(data) do
      {:ok, %Identifier{type: ^type, value: value}} ->
        {:ok, value}

      {:ok, %Identifier{type: received_type}} ->
        {:error, "#{__MODULE__}: Unexpected type. Expected #{type}, but got #{received_type}"}

      {:error, _} = error ->
        error
    end
  end

  @spec encode_list_to_binary(list(t())) :: list(binary())
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
