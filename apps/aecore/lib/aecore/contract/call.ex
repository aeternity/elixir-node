defmodule Aecore.Contract.Call do
  alias Aecore.Chain.Identifier
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aeutil.Hash

  @type call :: %{
          caller_address: Identifier.t(),
          caller_nonce: integer(),
          height: integer(),
          contract_address: Identifier.t(),
          gas_price: non_neg_integer(),
          gas_used: non_neg_integer(),
          return_value: binary(),
          return_type: :ok | :error | :revert
        }

  @type t :: call()
  @type hash :: binary()

  @nonce_size 256

  @spec new_call(hash(), non_neg_integer(), hash(), non_neg_integer(), non_neg_integer()) ::
          call()
  def new_call(caller, nonce, block_height, contract_address, gas_price) do
    %{
      :caller_address => caller,
      :caller_nonce => nonce,
      :height => block_height,
      :contract_address => contract_address,
      :gas_price => gas_price,
      :gas_used => 0,
      :return_value => <<>>,
      :return_type => :ok
    }
  end

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), map()) ::
          binary() | {:error, String.t()}
  def rlp_encode(tag, version, %{} = call) do
    {:ok, encoded_caller_address} = Identifier.encode_data(call.caller_address)
    {:ok, encoded_contract_address} = Identifier.encode_data(call.contract_address)

    list = [
      tag,
      version,
      encoded_caller_address,
      call.caller_nonce,
      call.height,
      encoded_contract_address,
      call.gas_price,
      call.gas_used,
      call.return_value,
      Parser.to_string(call.return_type)
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}:" <> Exception.message(e)}
    end
  end

  @spec rlp_decode(list()) :: {:ok, map()} | {:error, String.t()}
  def rlp_decode([
        encoded_caller_address,
        caller_nonce,
        height,
        encoded_contract_address,
        gas_price,
        gas_used,
        return_value,
        return_type
      ]) do
    {:ok, decoded_caller_address} = Identifier.decode_data(encoded_caller_address)
    {:ok, decoded_contract_address} = Identifier.decode_data(encoded_contract_address)

    {:ok,
     %{
       caller_address: decoded_caller_address,
       caller_nonce: Serialization.transform_item(caller_nonce, :int),
       height: Serialization.transform_item(height, :int),
       contract_address: decoded_contract_address,
       gas_price: Serialization.transform_item(gas_price, :int),
       gas_used: Serialization.transform_item(gas_used, :int),
       return_value: return_value,
       return_type: String.to_atom(return_type)
     }}
  end

  def rlp_decode(_) do
    {:error, "#{__MODULE__} : Invalid Caller State serialization"}
  end

  @spec id(map()) :: binary()
  def id(call), do: id(call.caller_address, call.caller_nonce, call.contract_address)

  @spec id(binary(), non_neg_integer(), binary()) :: binary()
  def id(caller, nonce, contract) do
    binary = <<caller.value::binary, nonce::size(@nonce_size), contract.value::binary>>

    Hash.hash(binary)
  end
end
