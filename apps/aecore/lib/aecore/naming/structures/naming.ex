defmodule Aecore.Naming.Structures.Naming do
  alias Aecore.Naming.Structures.PreClaimTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Util
  alias Aeutil.Hash

  @pre_claim_ttl 300

  @client_ttl_limit 86400

  @claim_expire_by_relative_limit 50000

  @type pre_claim :: %{height: non_neg_integer(), commitment: PreClaimTx.commitment_hash()}

  @type claim :: %{
          height: non_neg_integer(),
          name: String.t(),
          pointers: String.t(),
          name_salt: String.t(),
          expires_by: non_neg_integer(),
          client_ttl: non_neg_integer()
        }

  @type chain_state_name :: :naming

  @type salt :: binary()

  @type t :: %Naming{
          pre_claims: [pre_claim()],
          claims: [claim()]
        }

  @doc """
  Definition of Naming structure

  ## Parameters
  - pre_claims: list of pre_claims
  """
  defstruct [:pre_claims, :claims]
  use ExConstructor

  @spec empty() :: Naming.t()
  def empty() do
    %Naming{pre_claims: [], claims: []}
  end

  @spec create_pre_claim(non_neg_integer(), PreClaimTx.commitment_hash()) :: pre_claim()
  def create_pre_claim(height, commitment), do: %{:height => height, :commitment => commitment}

  @spec create_claim(
          non_neg_integer(),
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) :: claim()
  def create_claim(height, name, name_salt, expire_by, client_ttl, pointers),
    do: %{
      :height => height,
      :name => name,
      :name_salt => name_salt,
      :pointers => pointers,
      :expires_by => expire_by,
      :client_ttl => client_ttl
    }

  @spec create_claim(non_neg_integer(), String.t(), String.t()) :: claim()
  def create_claim(height, name, name_salt),
    do: %{
      :height => height,
      :name => name,
      :name_salt => name_salt,
      :pointers => "",
      :expires_by => height + @claim_expire_by_relative_limit,
      :client_ttl => @client_ttl_limit
    }

  @spec create_commitment_hash(String.t(), Naming.salt()) :: binary()
  def create_commitment_hash(name, name_salt) when is_binary(name_salt) do
    Hash.hash(Util.normalized_namehash!(name) <> name_salt)
  end

  @spec get_claim_expire_by_relative_limit() :: non_neg_integer()
  def get_claim_expire_by_relative_limit, do: @claim_expire_by_relative_limit

  @spec get_client_ttl_limit() :: non_neg_integer()
  def get_client_ttl_limit, do: @client_ttl_limit

  @spec apply_block_height_on_state!(ChainState.chainstate(), integer()) ::
          ChainState.chainstate()
  def apply_block_height_on_state!(%{naming: namingstate} = chainstate, block_height) do
    updated_naming_state =
      Enum.reduce(namingstate, %{}, fn {account, naming}, acc_naming_state ->
        updated_naming_pre_claims =
          Enum.filter(naming.pre_claims, fn pre_claim ->
            pre_claim.height + @pre_claim_ttl > block_height
          end)

        updated_naming_claims =
          Enum.filter(naming.claims, fn claim ->
            claim.expires_by > block_height
          end)

        updated_naming = %{naming | pre_claims: updated_naming_pre_claims, claims: updated_naming_claims}

        # prune empty naming states
        if(!Enum.empty?(updated_naming.pre_claims) || !Enum.empty?(updated_naming.claims)) do
          Map.put(acc_naming_state, account, updated_naming)
        else
          acc_naming_state
        end
      end)

    %{chainstate | naming: updated_naming_state}
  end
end
