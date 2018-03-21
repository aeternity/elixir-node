defmodule Aecore.Naming.Structures.Naming do
  alias Aecore.Naming.Structures.PreClaimTx
  alias Aecore.Naming.Structures.Naming

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
end
