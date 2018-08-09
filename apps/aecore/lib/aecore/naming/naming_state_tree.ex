defmodule Aecore.Naming.NamingStateTree do
  @moduledoc """
  Top level naming state tree.
  """
  alias Aecore.Naming.Naming
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

  @spec put(namings_state(), binary(), Naming.t()) :: namings_state()
  def put(tree, key, value) do
    serialized = serialize(value)
    PatriciaMerkleTree.enter(tree, key, serialized)
  end

  @spec get(namings_state(), binary()) :: Naming.t() | :none
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      {:ok, value} ->
        {:ok, naming} = deserialize(value)

        identified_hash =
          case naming do
            %{
              owner: _owner,
              created: _created,
              expires: _expires
            } ->
              {:ok, identified_commitment_hash} = Identifier.create_identity(key, :commitment)
              identified_commitment_hash

            %{
              owner: _owner,
              expires: _expires,
              status: _status,
              ttl: _ttl,
              pointers: _pointers
            } ->
              {:ok, identified_name_hash} = Identifier.create_identity(key, :name)
              identified_name_hash
          end

        Map.put(naming, :hash, identified_hash)

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

  defp serialize(
         %{
           owner: _owner,
           created: _created,
           expires: _expires
         } = term
       ) do
    Serialization.rlp_encode(term, :name_commitment)
  end

  defp serialize(
         %{
           owner: _owner,
           expires: _expires,
           status: _status,
           ttl: _ttl,
           pointers: _pointers
         } = term
       ) do
    Serialization.rlp_encode(term, :naming_state)
  end

  defp deserialize(binary) do
    Serialization.rlp_decode(binary)
  end
end
