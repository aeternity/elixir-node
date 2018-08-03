defmodule Aecore.Naming.NameCommitment do
  @moduledoc """
  Aecore naming name commitment structure
  """

  alias Aecore.Naming.{NameCommitment, NameUtil}
  alias Aeutil.Bits
  alias Aeutil.Hash
  alias Aeutil.Serialization

  @version 1

  @type salt :: binary()

  @type t :: %NameCommitment{
          hash: binary(),
          owner: Wallet.pubkey(),
          created: non_neg_integer(),
          expires: non_neg_integer()
        }

  defstruct [:hash, :owner, :created, :expires]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: t()
  def create(hash, owner, created, expires),
    do: %NameCommitment{
      :hash => hash,
      :owner => owner,
      :created => created,
      :expires => expires
    }

  @spec hash(String.t(), salt()) :: {:ok, binary()} | {:error, String.t()}
  def hash(name, name_salt) when is_binary(name_salt) do
    case NameUtil.normalized_namehash(name) do
      {:ok, hash} ->
        {:ok, Hash.hash(hash <> name_salt)}

      err ->
        err
    end
  end

  def base58c_encode_commitment(bin) do
    Bits.encode58c("cm", bin)
  end

  def base58c_decode_commitment(<<"cm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_commitment(_) do
    {:error, "Wrong data"}
  end

  def encode_to_list(%NameCommitment{} = name_commitment) do
    [
      @version,
      name_commitment.hash,
      name_commitment.owner,
      name_commitment.created,
      name_commitment.expires
    ]
  end

  def decode_from_list(@version, [hash, owner, created, expires]) do
    {:ok,
     %NameCommitment{
       hash: hash,
       owner: owner,
       created: Serialization.transform_item(created, :int),
       expires: Serialization.transform_item(expires, :int)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
