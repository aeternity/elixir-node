defmodule Aecore.Naming.Structures.Naming do
  alias Aecore.Naming.Structures.PreClaimTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Chain.ChainState

  @pre_claim_ttl 300

  @type pre_claim :: %{height: non_neg_integer(), commitment: PreClaimTx.commitment_hash()}

  @type claim :: %{height: non_neg_integer(), name: String.t(), pointers: String.t()}

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

  @spec create_claim(non_neg_integer(), String.t()) :: claim()
  def create_claim(height, name), do: %{:height => height, :name => name, :pointers => ""}

  @spec apply_block_height_on_state!(ChainState.chainstate(), integer()) ::
          ChainState.chainstate()
  def apply_block_height_on_state!(%{naming: namingstate} = chainstate, block_height) do
    updated_naming_state =
      Enum.reduce(namingstate, %{}, fn {account, naming}, acc_naming_state ->
        updated_naming_pre_claims =
          Enum.filter(naming.pre_claims, fn pre_claim ->
            pre_claim.height + @pre_claim_ttl > block_height
          end)

        updated_naming = %{naming | pre_claims: updated_naming_pre_claims}

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
