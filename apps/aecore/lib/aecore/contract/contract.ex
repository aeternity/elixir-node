defmodule Aecore.Contract.Contract do

  alias Aecore.Chain.Identifier
  alias Aeutil.Serialization

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

  def rlp_encode(tag, version, contract) do
    {:ok, encoded_owner} = Identifier.encode_data(contract.owner)

    active = case contract.active do
      true -> 1
      false -> 0
    end

    encoded_referers =
      Enum.reduce(contract.referers, [], fn referer, acc ->
        {:ok, encoded_referer} = Identifier.encode_data(referer)
        [encoded_referer | acc]
      end)
      |> Enum.reverse()

    list =
      [
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
      e -> {:errorrr, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_decode(
      [
        owner,
        vm_version,
        code,
        log,
        active,
        referers,
        deposit
      ]
    ) do
      {:ok, decoded_owner_address} = Identifier.decode_data(owner)
      decoded_active =
        case Serialization.transform_item(active, :int) do
          0 -> false
          1 -> true
        end

      decoded_referers =
        Enum.reduce(referers, [], fn referer, acc ->
          {:ok, decoded_referer} = Identifier.decode_data(referer)

          [decoded_referer | acc]
        end)
        |> Enum.reverse()

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
        }
      }
  end

  def store_id(contract) do
    id = contract.id

    <<id.value::binary, @store_prefix>>
  end

end
