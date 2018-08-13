defmodule Aecore.Naming.NameClaim do
  @moduledoc """
  Aecore naming name claim structure
  """

  alias Aecore.Keys.Wallet
  alias Aeutil.Bits
  alias Aeutil.Serialization
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.NameClaim
  alias Aecore.Chain.Identifier

  @version 1

  @name_salt_byte_size 32

  @type name_status() :: :claimed | :revoked

  @type salt :: binary()

  @type hash :: binary()

  @type t :: %NameClaim{
          hash: binary(),
          name: binary(),
          owner: Wallet.pubkey(),
          expires: non_neg_integer(),
          status: name_status(),
          ttl: non_neg_integer(),
          pointers: list()
        }

  defstruct [:hash, :name, :owner, :expires, :status, :ttl, :pointers]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: t()
  def create(hash, name, owner, expire_by, client_ttl, pointers) do
    identified_hash = Identifier.create_identity(hash, :name)
    identified_owner = Identifier.create_identity(owner, :account)

    %NameClaim{
      :hash => identified_hash,
      :name => name,
      :owner => identified_owner,
      :expires => expire_by,
      :status => :claimed,
      :ttl => client_ttl,
      :pointers => pointers
    }
  end

  @spec create(binary(), binary(), Wallet.pubkey(), non_neg_integer()) :: t()
  def create(hash, name, owner, height) do
    identified_hash = Identifier.create_identity(hash, :name)
    identified_owner = Identifier.create_identity(owner, :account)

    %NameClaim{
      :hash => identified_hash,
      :name => name,
      :owner => identified_owner,
      :expires => height + GovernanceConstants.claim_expire_by_relative_limit(),
      :status => :claimed,
      :ttl => GovernanceConstants.client_ttl_limit(),
      :pointers => []
    }
  end

  @spec get_name_salt_byte_size() :: non_neg_integer()
  def get_name_salt_byte_size, do: @name_salt_byte_size

  def base58c_encode_hash(bin) do
    Bits.encode58c("nm", bin)
  end

  def base58c_decode_hash(<<"nm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_hash(_) do
    {:error, "Wrong data"}
  end

  @spec encode_to_list(t()) :: binary()
  def encode_to_list(%NameClaim{} = naming_state) do
    [
      @version,
      Identifier.encode_to_binary(naming_state.owner),
      naming_state.expires,
      Atom.to_string(naming_state.status),
      naming_state.ttl,
      naming_state.pointers
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, t()} | {:error, String.t()}
  def decode_from_list(@version, [encoded_owner, expires, status, ttl, pointers]) do
    case Identifier.decode_from_binary(encoded_owner) do
      {:ok, owner} ->
        {:ok,
         %NameClaim{
           owner: owner,
           expires: Serialization.transform_item(expires, :int),
           status: String.to_atom(status),
           ttl: Serialization.transform_item(ttl, :int),
           pointers: pointers
         }}

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
