defmodule Aecore.Contract.Call do
  @moduledoc """
  Module defining the structure of a contract call
  """

  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Contract.{Call, CallStateTree}
  alias Aecore.Contract.Tx.ContractCallTx
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys
  alias Aeutil.Hash

  require Logger

  @version 1

  @typedoc "Structure of the Call Transaction type"
  @type t :: %Call{
          caller_address: Keys.pubkey(),
          caller_nonce: integer(),
          height: integer(),
          contract_address: Keys.pubkey(),
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

  @spec call_contract(
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          list(binary()),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok | :error
  def call_contract(
        contract,
        vm_version,
        amount,
        gas,
        gas_price,
        call_data,
        call_stack,
        fee,
        ttl \\ 0
      ) do
    payload = %{
      contract: contract,
      vm_version: vm_version,
      amount: amount,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data,
      call_stack: call_stack
    }

    {pubkey, privkey} = Keys.keypair(:sign)

    tx_data =
      DataTx.init(
        ContractCallTx,
        payload,
        pubkey,
        fee,
        Chain.lowest_valid_nonce(),
        ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, privkey)

    Pool.add_transaction(tx)
  end

  @spec new(Keys.pubkey(), non_neg_integer(), non_neg_integer(), Keys.pubkey(), non_neg_integer()) ::
          Call.t()
  def new(caller_address, nonce, block_height, contract_address, gas_price) do
    %Call{
      :caller_address => caller_address,
      :caller_nonce => nonce,
      :height => block_height,
      :contract_address => contract_address,
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
    encoded_return_type = encode_return_type(return_type)

    [
      @version,
      caller_address,
      :binary.encode_unsigned(caller_nonce),
      :binary.encode_unsigned(height),
      contract_address,
      :binary.encode_unsigned(gas_price),
      :binary.encode_unsigned(gas_used),
      return_value,
      encoded_return_type
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Call.t()} | {:error, String.t()}
  def decode_from_list(@version, [
        caller_address,
        caller_nonce,
        height,
        contract_address,
        gas_price,
        gas_used,
        return_value,
        return_type
      ]) do
    decoded_return_type = decode_return_type(return_type)

    case decoded_return_type do
      decoded_return_type when decoded_return_type in [:ok, :error, :revert] ->
        {:ok,
         %Call{
           caller_address: caller_address,
           caller_nonce: :binary.decode_unsigned(caller_nonce),
           height: :binary.decode_unsigned(height),
           contract_address: contract_address,
           gas_price: :binary.decode_unsigned(gas_price),
           gas_used: :binary.decode_unsigned(gas_used),
           return_value: return_value,
           return_type: decoded_return_type
         }}

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
    id(caller_address, caller_nonce, contract_address)
  end

  @spec id(Keys.pubkey(), non_neg_integer(), Keys.pubkey()) :: binary()
  def id(caller_address, caller_nonce, contract_address) do
    binary = <<caller_address::binary, caller_nonce::size(@nonce_size), contract_address::binary>>

    Hash.hash(binary)
  end

  @spec prune_calls(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def prune_calls(chainstate, block_height) do
    CallStateTree.prune(chainstate, block_height)
  end

  defp encode_return_type(return_type) when is_atom(return_type) do
    case return_type do
      :ok -> <<0>>
      :error -> <<1>>
      :revert -> <<2>>
    end
  end

  defp decode_return_type(return_type) do
    case return_type do
      <<0>> -> :ok
      <<1>> -> :error
      <<2>> -> :revert
    end
  end
end
