defmodule Aecore.Contract.Call do
  @moduledoc """
  Module defining the structure of a contract call
  """
  alias Aecore.Chain.Identifier
  alias Aecore.Contract.Call
  alias Aeutil.Parser
  alias Aeutil.Hash

  @version 1

  @typedoc "Structure of the Call Transaction type"
  @type t :: %Call{
          caller_address: Identifier.t(),
          caller_nonce: integer(),
          height: integer(),
          contract_address: Identifier.t(),
          gas_price: non_neg_integer(),
          gas_used: non_neg_integer(),
          return_value: binary(),
          return_type: :ok | :error | :revert
        }

  @type hash :: binary()

  defstruct [
    :caller_address,
    :caller_nonce,
    :height,
    :contract_address,
    :gas_price,
    :gas_used,
    :return_value,
    :return_type
  ]

  use Aecore.Util.Serializable

  @nonce_size 256

  @spec new(Keys.pubkey(), non_neg_integer(), non_neg_integer(), Keys.pubkey(), non_neg_integer()) ::
          Call.t()
  def new(caller_address, nonce, block_height, contract_address, gas_price) do
    identified_caller_address = Identifier.create_identity(caller_address, :account)
    identified_contract_address = Identifier.create_identity(contract_address, :contract)

    %Call{
      :caller_address => identified_caller_address,
      :caller_nonce => nonce,
      :height => block_height,
      :contract_address => identified_contract_address,
      :gas_price => gas_price,
      # will be set
      :gas_used => 0,
      # in the
      :return_value => <<>>,
      # ContractCallTx.new
      :return_type => :ok
    }
  end

  @spec encode_to_list(Call.t()) :: list()
  def encode_to_list(%Call{
        caller_address: caller_address,
        caller_nonce: caller_nonce,
        height: height,
        contract_address: contract_address,
        gas_price: gas_price,
        gas_used: gas_used,
        return_value: return_value,
        return_type: return_type
      }) do
    [
      @version,
      Identifier.encode_to_binary(caller_address),
      :binary.encode_unsigned(caller_nonce),
      :binary.encode_unsigned(height),
      Identifier.encode_to_binary(contract_address),
      :binary.encode_unsigned(gas_price),
      :binary.encode_unsigned(gas_used),
      return_value,
      Parser.to_string(return_type)
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Call.t()} | {:error, String.t()}
  def decode_from_list(@version, [
        encoded_caller_address,
        caller_nonce,
        height,
        encoded_contract_address,
        gas_price,
        gas_used,
        return_value,
        return_type
      ]) do
    case return_type do
      return_type when return_type in ["ok", "error", "revert"] ->
        parsed_return_type = String.to_atom(return_type)

        with {:ok, decoded_caller_address} <-
               Identifier.decode_from_binary(encoded_caller_address),
             {:ok, decoded_contract_address} <-
               Identifier.decode_from_binary(encoded_contract_address) do
          {:ok,
           %Call{
             caller_address: decoded_caller_address,
             caller_nonce: :binary.decode_unsigned(caller_nonce),
             height: :binary.decode_unsigned(height),
             contract_address: decoded_contract_address,
             gas_price: :binary.decode_unsigned(gas_price),
             gas_used: :binary.decode_unsigned(gas_used),
             return_value: return_value,
             return_type: parsed_return_type
           }}
        else
          {:error, _} = error -> error
        end

      _ ->
        {:error, "#{__MODULE__}: decode_from_list: Invalid return_type: #{inspect(return_type)}"}
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end

  @spec id(Call.t()) :: binary()
  def id(%Call{
        caller_address: caller_address,
        caller_nonce: caller_nonce,
        contract_address: contract_address
      }) do
    binary =
      <<caller_address.value::binary, caller_nonce::size(@nonce_size),
        contract_address.value::binary>>

    Hash.hash(binary)
  end
end
