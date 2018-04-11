defmodule Aecore.Naming.Naming do
  alias Aecore.Naming.Naming
  alias Aecore.Chain.ChainState
  alias Aecore.Naming.NameUtil
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Hash
  alias Aeutil.Bits

  @pre_claim_ttl 300

  @revoke_expiration_ttl 2016

  @client_ttl_limit 86400

  @claim_expire_by_relative_limit 50000

  @name_salt_byte_size 32

  @type name_status() :: :claimed | :revoked

  @type claim :: %{
          hash: binary(),
          name: String.t(),
          owner: Wallet.pubkey(),
          expires: non_neg_integer(),
          status: name_status(),
          ttl: non_neg_integer(),
          pointers: list()
        }

  @type commitment :: %{
          hash: binary(),
          owner: Wallet.pubkey(),
          created: non_neg_integer(),
          expires: non_neg_integer()
        }

  @type chain_state_name :: :naming

  @type salt :: binary()

  @type hash :: binary()

  @type t :: claim() | commitment()

  @spec create_commitment(
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: commitment()
  def create_commitment(hash, owner, created, expires),
    do: %{
      :hash => hash,
      :owner => owner,
      :created => created,
      :expires => expires
    }

  @spec create_claim(
          binary(),
          String.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: claim()
  def create_claim(hash, name, owner, expire_by, client_ttl, pointers),
    do: %{
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => expire_by,
      :status => :claimed,
      :ttl => client_ttl,
      :pointers => pointers
    }

  @spec create_claim(binary(), String.t(), Wallet.pubkey(), non_neg_integer()) :: claim()
  def create_claim(hash, name, owner, height),
    do: %{
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => height + @claim_expire_by_relative_limit,
      :status => :claimed,
      :ttl => @client_ttl_limit,
      :pointers => []
    }

  @spec create_commitment_hash(String.t(), Naming.salt()) :: binary()
  def create_commitment_hash(name, name_salt) when is_binary(name_salt) do
    Hash.hash(NameUtil.normalized_namehash!(name) <> name_salt)
  end

  @spec get_claim_expire_by_relative_limit() :: non_neg_integer()
  def get_claim_expire_by_relative_limit, do: @claim_expire_by_relative_limit

  @spec get_client_ttl_limit() :: non_neg_integer()
  def get_client_ttl_limit, do: @client_ttl_limit

  @spec get_name_salt_byte_size() :: non_neg_integer()
  def get_name_salt_byte_size, do: @name_salt_byte_size

  @spec get_revoke_expiration_ttl() :: non_neg_integer()
  def get_revoke_expiration_ttl, do: @revoke_expiration_ttl

  @spec get_pre_claim_ttl() :: non_neg_integer()
  def get_pre_claim_ttl, do: @pre_claim_ttl

  @spec apply_block_height_on_state!(ChainState.chainstate(), integer()) ::
          ChainState.chainstate()
  def apply_block_height_on_state!(%{naming: naming_state} = chainstate, block_height) do
    updated_naming_state =
      naming_state
      |> Enum.filter(fn {_hash, name_state} -> name_state.expires > block_height end)
      |> Enum.into(%{})

    %{chainstate | naming: updated_naming_state}
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

  def base58c_encode_commitment(bin) do
    Bits.encode58c("cm", bin)
  end

  def base58c_decode_commitment(<<"cm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_commitment(_) do
    {:error, "Wrong data"}
  end
end
