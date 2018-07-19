defmodule Aecore.Naming.NameClaim do
  @moduledoc """
  Aecore naming name claim structure
  """

  @behaviour Aeutil.Serializable

  alias Aecore.Keys.Wallet
  alias Aeutil.Bits
  alias Aeutil.Serialization
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.NameClaim

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

  @spec create(
          binary(),
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: t()
  def create(hash, name, owner, expire_by, client_ttl, pointers),
    do: %NameClaim{
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => expire_by,
      :status => :claimed,
      :ttl => client_ttl,
      :pointers => pointers
    }

  @spec create(binary(), binary(), Wallet.pubkey(), non_neg_integer()) :: t()
  def create(hash, name, owner, height),
    do: %NameClaim{
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => height + GovernanceConstants.claim_expire_by_relative_limit(),
      :status => :claimed,
      :ttl => GovernanceConstants.client_ttl_limit(),
      :pointers => []
    }

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
      naming_state.hash,
      naming_state.owner,
      naming_state.expires,
      Atom.to_string(naming_state.status),
      naming_state.ttl,
      naming_state.pointers
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, t()} | {:error, String.t()}
  def decode_from_list(@version, [hash, owner, expires, status, ttl, pointers]) do
    {:ok,
     %NameClaim{
       hash: hash,
       owner: owner,
       expires: Serialization.transform_item(expires, :int),
       status: String.to_atom(status),
       ttl: Serialization.transform_item(ttl, :int),
       pointers: pointers
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
