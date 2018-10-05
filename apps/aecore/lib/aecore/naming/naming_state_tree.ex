defmodule Aecore.Naming.NamingStateTree do
  @moduledoc """
  Top level naming state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Naming.{Name, NameCommitment}
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier
  alias MerklePatriciaTree.Trie

  @typedoc "Namings tree"
  @type namings_state() :: Trie.t()

  @spec name() :: atom()
  def name(), do: :naming

  @spec get(namings_state(), binary()) :: Name.t() | NameCommitment.t() | :none
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      {:ok, value} ->
        {:ok, naming} = Serialization.rlp_decode_anything(value)

        case naming do
          %Name{} ->
            hash = Identifier.create_identity(key, :name)
            %Name{naming | hash: hash}

          %NameCommitment{} ->
            hash = Identifier.create_identity(key, :commitment)
            %NameCommitment{naming | hash: hash}
        end

      _ ->
        :none
    end
  end
end
