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

  @type salt :: integer()

  @type hash :: binary()

  @type t :: %NameClaim{
          hash: binary(),
          owner: Wallet.pubkey(),
          expires: non_neg_integer(),
          status: name_status(),
          ttl: non_neg_integer(),
          pointers: list()
        }

  defstruct [:hash, :owner, :expires, :status, :ttl, :pointers]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: t()
  def create(hash, owner, expire_by, _client_ttl, pointers \\ "[]") do   ## TODO: Claint_ttl shouln't be ignored
    identified_hash = Identifier.create_identity(hash, :name)

    %NameClaim{
      :hash => identified_hash,
      :owner => owner,
      :expires => expire_by,
      :status => :claimed,
      :ttl => 0,   ## TODO: Should be changed to client_ttl
      :pointers => pointers
    }
  end

  @spec create(binary(), Wallet.pubkey(), non_neg_integer()) :: t()
  def create(hash, owner, height) do
    identified_hash = Identifier.create_identity(hash, :name)

    %NameClaim{
      :hash => identified_hash,
      :owner => owner,
      :expires => height + GovernanceConstants.claim_expire_by_relative_limit(),
      :status => :claimed,
      :ttl => GovernanceConstants.client_ttl_limit(),
      :pointers => "[]"
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
      :binary.encode_unsigned(@version),
      naming_state.owner,
      :binary.encode_unsigned(naming_state.expires),
      Atom.to_string(naming_state.status),
      :binary.encode_unsigned(naming_state.ttl),
      naming_state.pointers      # maybe Poison.encode!()
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, t()} | {:error, String.t()}
  def decode_from_list(@version, [owner, expires, status, ttl, pointers]) do
        {:ok,
         %NameClaim{
           owner: owner,
           expires: :binary.decode_unsigned(expires),
           status: String.to_atom(status),
           ttl: :binary.decode_unsigned(ttl),
           pointers: pointers   # maybe Poison.dencode!()
         }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
