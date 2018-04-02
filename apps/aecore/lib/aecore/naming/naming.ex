defmodule Aecore.Naming.Naming do
  alias Aecore.Naming.Structures.NamePreClaimTx
  alias Aecore.Naming.Naming
  alias Aecore.Chain.ChainState
  alias Aecore.Naming.NameUtil
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Hash

  @pre_claim_ttl 300

  @client_ttl_limit 86400

  @claim_expire_by_relative_limit 50000

  @name_salt_byte_size 32

  @type claim :: %{
          name: String.t(),
          owner: Wallet.pubkey(),
          expires_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @type chain_state_name :: :naming

  @type salt :: binary()

  @type hash :: binary()

  @type t :: claim() | NamePreClaimTx.commitment_hash()

  @spec create_claim(
          String.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) :: claim()
  def create_claim(name, owner, expire_by, client_ttl, pointers),
    do: %{
      :name => name,
      :owner => owner,
      :expires_by => expire_by,
      :client_ttl => client_ttl,
      :pointers => pointers
    }

  @spec create_claim(String.t(), Wallet.pubkey(), non_neg_integer()) :: claim()
  def create_claim(name, owner, height),
    do: %{
      :name => name,
      :owner => owner,
      :expires_by => height + @claim_expire_by_relative_limit,
      :client_ttl => @client_ttl_limit,
      :pointers => ""
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

  @spec apply_block_height_on_state!(ChainState.chainstate(), integer()) ::
          ChainState.chainstate()
  def apply_block_height_on_state!(%{naming: naming_state} = chainstate, block_height) do
    # TODO remove pre claims after ttl
    # TODO remove expired claims
    # TODO remove revoked after 2016 blocks

    %{chainstate | naming: naming_state}
  end
end
