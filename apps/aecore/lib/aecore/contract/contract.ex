defmodule Aecore.Contract.Contract do
  @moduledoc """
  Aecore contact module implementation.
  """
  alias Aecore.Chain.Identifier
  alias Aeutil.Serialization
  alias Aecore.Keys.Wallet
  alias Aeutil.Hash

  @store_prefix 16

  @type contract :: %{
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

  @spec new(Wallet.pubkey(), non_neg_integer(), byte(), binary(), non_neg_integer()) :: contract()
  def new(owner, nonce, vm_version, code, deposit) do
    contract_id = create_contract_id(owner, nonce)
    {:ok, identified_contract} = Identifier.create_identity(contract_id, :contract)
    {:ok, identified_owner} = Identifier.create_identity(owner, :account)
    %{
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

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), contract()) :: binary() | {:error, String.t()}
  def rlp_encode(tag, version, contract) do
    {:ok, encoded_owner} = Identifier.encode_data(contract.owner)

    active =
      case contract.active do
        true -> 1
        false -> 0
      end

    raw_encoded_referers =
      Enum.reduce(contract.referers, [], fn referer, acc ->
        {:ok, encoded_referer} = Identifier.encode_data(referer)
        [encoded_referer | acc]
      end)

    encoded_referers = raw_encoded_referers |> Enum.reverse()

    list = [
      tag,
      version,
      encoded_owner,
      contract.vm_version,
      contract.code,
      contract.log,
      active,
      encoded_referers,
      contract.deposit
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  @spec rlp_decode(list()) :: {:ok, map()} | {:error, String.t()}
  def rlp_decode([
        owner,
        vm_version,
        code,
        log,
        active,
        referers,
        deposit
      ]) do
    {:ok, decoded_owner_address} = Identifier.decode_data(owner)

    decoded_active =
      case Serialization.transform_item(active, :int) do
        0 -> false
        1 -> true
      end

    raw_decoded_referers =
      Enum.reduce(referers, [], fn referer, acc ->
        {:ok, decoded_referer} = Identifier.decode_data(referer)

        [decoded_referer | acc]
      end)

    decoded_referers = raw_decoded_referers |> Enum.reverse()

    {:ok,
     %{
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

  @spec store_id(contract()) :: binary()
  def store_id(contract) do
    id = contract.id

    <<id.value::binary, @store_prefix>>
  end

  defp create_contract_id(owner, nonce) do
    nonce_binary = :binary.encode_unsigned(nonce)

    Hash.hash(<<owner::binary, nonce_binary::binary>>)
  end
end
