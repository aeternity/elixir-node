defmodule Aecore.Chain.Identifier do
  alias __MODULE__

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
  @type t() :: %Identifier{type: type(), value: value()}
  @type type() :: :account | :name | :commitment | :oracle | :contract | :channel
  # byte_size should be 32 byte
  @type value() :: binary()
  defstruct type: :undefined, value: ""
  use ExConstructor

  @spec create_identity(type(), value()) :: Identifier.t() | {:error, String.t()}
  # byte_size(data) == 32 data should be stricted to 32 bytes only
  def create_identity(value, type) when is_atom(type) and is_binary(value) do
    case Application.get_env(:aecore, :binary_ids)[type] do
      nil ->
        {:error,
         "#{__MODULE__}: The following tag: #{inspect(type)} for given value: #{inspect(value)} doesn't exist"}

      tag when is_integer(tag) ->
        {:ok, %Identifier{type: type, value: value}}

      _ ->
        create_identity(value, type)
    end
  end

  def create_identity(data, type) do
    {:error,
     "Could not create an id, reason: Invalid data: #{inspect(data)} or type: #{inspect(type)}"}
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
  @spec encode_data(Identifier.t()) :: {:error, String.t()} | {:ok, binary()}
  def encode_data(%Identifier{} = data) do
    case Application.get_env(:aecore, :binary_ids)[data.type] do
      nil ->
        {:error,
         "Binary tag for the given type: #{inspect(data.type)} doesn't exist, or the data is corrupted: #{
           inspect(data)
         }"}

      # data should be stricted to 32 bytes only
      tag ->
        {:ok, <<tag::unsigned-integer-size(8), data.value::binary>>}
    end
  end

  # byte_size(data) == 33 # data should be stricted to 32 bytes only
  @spec decode_data(binary()) :: tuple() | {:error, String.t()}
  def decode_data(<<tag::unsigned-integer-size(8), data::binary>>)
      when is_binary(data) do
    case specify_data(tag) do
      {:error, msg} ->
        {:error, msg}

      {_type, _tag} ->
        {:ok, data}
    end
  end

  @spec specify_data(non_neg_integer()) :: tuple() | {:error, String.t()}
  # data should be stricted to 32 bytes only
  defp specify_data(tag) when is_integer(tag) do
    error_message = {:error, "#{__MODULE__}: Tag doesn't exist: #{inspect(tag)}"}

    Enum.find(Application.get_env(:aecore, :binary_ids), error_message, fn elem ->
      {_known_type, known_tag} = elem
      tag == known_tag
    end)
  end
end
