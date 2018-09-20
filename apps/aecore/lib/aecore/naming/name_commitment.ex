defmodule Aecore.Naming.NameCommitment do
  @moduledoc """
  Module defining the structure of a name commitment
  """
  alias Aecore.Chain.Identifier
  alias Aecore.Keys
  alias Aecore.Naming.{NameCommitment, NameUtil}
  alias Aeutil.{Bits, Hash, Serialization}

  @version 1

  @type salt :: integer()

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Structure of the NameCommitment Transaction type"
  @type t :: %NameCommitment{
          hash: binary(),
          owner: Keys.pubkey(),
          created: non_neg_integer(),
          expires: non_neg_integer()
        }

  defstruct [:hash, :owner, :created, :expires]
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: NameCommitment.t()
  def create(hash, owner, created, expires) do
    identified_hash = Identifier.create_identity(hash, :commitment)

    %NameCommitment{
      :hash => identified_hash,
      :owner => owner,
      :created => created,
      :expires => expires
    }
  end

  @spec commitment_hash(String.t(), salt()) :: {:ok, binary()} | {:error, reason()}
  def commitment_hash(name, name_salt) when is_integer(name_salt) do
    case NameUtil.normalize_and_validate_name(name) do
      {:ok, normalized_name} ->
        hash_name = Hash.hash(normalized_name)
        {:ok, Hash.hash(hash_name <> <<name_salt::integer-size(256)>>)}

      {:error, _} = error ->
        error
    end
  end

  @spec base58c_encode_commitment(binary()) :: String.t()
  def base58c_encode_commitment(bin) do
    Bits.encode58c("cm", bin)
  end

  @spec base58c_decode_commitment(String.t()) :: binary() | {:error, reason()}
  def base58c_decode_commitment(<<"cm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_commitment(_) do
    {:error, "Wrong data"}
  end

  @spec encode_to_list(NameCommitment.t()) :: list()
  def encode_to_list(%NameCommitment{owner: owner, created: created, expires: expires}) do
    [
      :binary.encode_unsigned(@version),
      owner,
      :binary.encode_unsigned(created),
      :binary.encode_unsigned(expires)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) ::
          {:ok, NameCommitment.t()} | {:error, reason()}
  def decode_from_list(@version, [encoded_owner, created, expires]) do
    {:ok,
     %NameCommitment{
       owner: encoded_owner,
       created: :binary.decode_unsigned(created),
       expires: :binary.decode_unsigned(expires)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
