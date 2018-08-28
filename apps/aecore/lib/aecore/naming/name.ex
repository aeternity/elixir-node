defmodule Aecore.Naming.Name do
  @moduledoc """
  Aecore naming name structure
  """

  alias Aecore.Keys
  alias Aeutil.Bits
  alias Aeutil.Serialization
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.Name
  alias Aecore.Chain.Identifier

  @version 1

  @type name_status() :: :claimed | :revoked

  @type salt :: integer()

  @type hash :: binary()

  @type t :: %Name{
          hash: binary(),
          owner: Keys.pubkey(),
          expires: non_neg_integer(),
          status: name_status(),
          client_ttl: non_neg_integer(),
          pointers: list()
        }

  defstruct [:hash, :owner, :expires, :status, :client_ttl, :pointers]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: t()
  def create(hash, owner, expire_by, client_ttl, pointers \\ "[]") do
    identified_hash = Identifier.create_identity(hash, :name)

    %Name{
      :hash => identified_hash,
      :owner => owner,
      :expires => expire_by,
      :status => :claimed,
      :client_ttl => client_ttl,
      :pointers => pointers
    }
  end

  @spec create(binary(), Keys.pubkey(), non_neg_integer()) :: t()
  def create(hash, owner, height) do
    identified_hash = Identifier.create_identity(hash, :name)

    %Name{
      :hash => identified_hash,
      :owner => owner,
      :expires => height + GovernanceConstants.claim_expire_by_relative_limit(),
      :status => :claimed,
      :client_ttl => 0,
      :pointers => "[]"
    }
  end

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
  def encode_to_list(%Name{
        owner: owner,
        expires: expires,
        status: status,
        client_ttl: client_ttl,
        pointers: pointers
      }) do
    [
      :binary.encode_unsigned(@version),
      owner,
      :binary.encode_unsigned(expires),
      Atom.to_string(status),
      :binary.encode_unsigned(client_ttl),
      pointers
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, t()} | {:error, String.t()}
  def decode_from_list(@version, [owner, expires, status, client_ttl, pointers]) do
    {:ok,
     %Name{
       owner: owner,
       expires: :binary.decode_unsigned(expires),
       status: String.to_atom(status),
       client_ttl: :binary.decode_unsigned(client_ttl),
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
