defmodule Aecore.Naming.Name do
  @moduledoc """
  Module defining the structure of a name
  """

  alias Aecore.Chain.Identifier
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Keys
  alias Aecore.Naming.Name
  alias Aeutil.{Bits, Serialization}

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @type name_status() :: :claimed | :revoked

  @type salt :: integer()

  @type hash :: binary()

  @typedoc "Structure of the Name Transaction type"
  @type t :: %Name{
          hash: Identifier.t(),
          owner: Keys.pubkey(),
          expires: non_neg_integer(),
          status: name_status(),
          client_ttl: non_neg_integer(),
          pointers: list()
        }

  defstruct [:hash, :owner, :expires, :status, :client_ttl, :pointers]
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: Name.t()
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

  @spec create(binary(), Keys.pubkey(), non_neg_integer()) :: Name.t()
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

  @spec base58c_encode_hash(hash()) :: String.t()
  def base58c_encode_hash(bin) do
    Bits.encode58c("nm", bin)
  end

  @spec base58c_decode_hash(String.t()) :: hash() | {:error, reason()}
  def base58c_decode_hash(<<"nm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_hash(_) do
    {:error, "Wrong data"}
  end

  @spec encode_to_list(Name.t()) :: list()
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

  @spec decode_from_list(integer(), list()) :: {:ok, Name.t()} | {:error, reason()}
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
