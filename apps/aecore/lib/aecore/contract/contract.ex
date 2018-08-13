defmodule Aecore.Contract.Contract do
  @moduledoc """
  Aecore contact module implementation.
  """
  alias Aecore.Contract.Contract
  alias Aecore.Chain.Identifier
  alias Aeutil.Serialization
  alias Aecore.Keys.Wallet
  alias Aeutil.Hash

  @version 1

  @store_prefix 16

  @type contract :: %Contract{
          id: Identifier.t(),
          owner: Identifier.t(),
          vm_version: byte(),
          code: binary(),
          store: %{binary() => binary()},
          log: binary(),
          active: boolean(),
          referers: [Identifier.t()],
          deposit: non_neg_integer()
        }

  @type t :: contract()

  defstruct [:id, :owner, :vm_version, :code, :store, :log, :active, :referers, :deposit]

  @spec new(Wallet.pubkey(), non_neg_integer(), byte(), binary(), non_neg_integer()) :: contract()
  def new(owner, nonce, vm_version, code, deposit) do
    contract_id = create_contract_id(owner, nonce)
    identified_contract = Identifier.create_identity(contract_id, :contract)
    identified_owner = Identifier.create_identity(owner, :account)

    %Contract{
      id: identified_contract,
      owner: identified_owner,
      vm_version: vm_version,
      code: code,
      store: %{},
      log: <<>>,
      active: true,
      referers: [],
      deposit: deposit
    }
  end

  @spec encode_to_list(Contract.t()) :: list()
  def encode_to_list(%Contract{} = contract) do
    active =
      case contract.active do
        true -> 1
        false -> 0
      end

    raw_encoded_referers =
      Enum.reduce(contract.referers, [], fn referer, acc ->
        encoded_referer = Identifier.encode_to_binary(referer)
        [encoded_referer | acc]
      end)

    encoded_referers = raw_encoded_referers |> Enum.reverse()

    [
      @version,
      Identifier.encode_to_binary(contract.owner),
      contract.vm_version,
      contract.code,
      contract.log,
      active,
      encoded_referers,
      contract.deposit
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, t()} | {:error, String.t()}
  def decode_from_list(@version, [
        owner,
        vm_version,
        code,
        log,
        active,
        referers,
        deposit
      ]) do
    {:ok, decoded_owner_address} = Identifier.decode_from_binary(owner)

    decoded_active =
      case Serialization.transform_item(active, :int) do
        0 -> false
        1 -> true
      end

    raw_decoded_referers =
      Enum.reduce(referers, [], fn referer, acc ->
        {:ok, decoded_referer} = Identifier.decode_from_binary(referer)

        [decoded_referer | acc]
      end)

    decoded_referers = raw_decoded_referers |> Enum.reverse()

    {:ok,
     %Contract{
       id: %Identifier{type: :contract},
       owner: decoded_owner_address,
       vm_version: Serialization.transform_item(vm_version, :int),
       code: code,
       store: %{},
       log: log,
       active: decoded_active,
       referers: decoded_referers,
       deposit: Serialization.transform_item(deposit, :int)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end

  @spec store_id(Contract.t()) :: binary()
  def store_id(contract) do
    id = contract.id

    <<id.value::binary, @store_prefix>>
  end

  defp create_contract_id(owner, nonce) do
    nonce_binary = :binary.encode_unsigned(nonce)

    Hash.hash(<<owner::binary, nonce_binary::binary>>)
  end
end
