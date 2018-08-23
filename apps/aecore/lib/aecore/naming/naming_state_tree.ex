defmodule Aecore.Naming.NamingStateTree do
  @moduledoc """
  Top level naming state tree.
  """
  alias Aecore.Naming.Name
  alias Aecore.Naming.NameCommitment
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier
  alias MerklePatriciaTree.Trie

  @type namings_state() :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: namings_state()
  def init_empty do
    PatriciaMerkleTree.new(:naming)
  end

  @spec put(namings_state(), binary(), Name.t() | NameCommitment.t()) :: namings_state()
  def put(tree, key, value) do
    serialized = Serialization.rlp_encode(value)
    PatriciaMerkleTree.enter(tree, key, serialized)
  end

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

  @spec delete(namings_state(), binary()) :: namings_state()
  def delete(tree, key) do
    PatriciaMerkleTree.delete(tree, key)
  end

  @spec root_hash(namings_state()) :: hash()
  def root_hash(tree) do
    PatriciaMerkleTree.root_hash(tree)
  end
end
