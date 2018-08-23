defmodule Aecore.Poi.PoiProof do
  @moduledoc """
    Implements a POI for a single Merkle Patricia Trie.
  """

  alias Aecore.Poi.PoiDB
  alias Aecore.Poi.PoiProof
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Trie.Storage
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB

  #This is the canonical root hash of an empty Patricia merkle tree
  @canonical_root_hash <<69, 176, 207, 194, 32, 206, 236, 91, 124, 28, 98, 196, 212, 25, 61, 56,
                         228, 235, 164, 142, 136, 21, 114, 156, 231, 95, 156, 10, 176, 228, 193,
                         192>>

  @state_hash_bytes 32

  @typedoc """
    Structure of a Poi proof for a single trie
  """
  @type t :: %PoiProof{
          root_hash: :empty | binary(),
          db: Map.t()
        }

  @doc """
    Definition of a Poi proof for a single trie

    ### Parameters
    - root_hash - contains the root hash of the associated merkle patricia trie
    - db -        contains the proof database. Any changes to this database via the PatriciaMerkleTree library
                  must be made via the ProofDB wrapper
  """
  defstruct [
    root_hash: :empty,
    db: %{},
  ]

  @doc """
    Creates a new Poi proof for a single Merkle Patricia Trie
  """
  @spec construct(Trie.t()) :: PoiProof.t()
  def construct(%Trie{} = trie) do
    %PoiProof{
      root_hash: trie_root_hash(trie),
    }
  end

  @doc """
    Creates a new Poi proof for an empty Merkle Patricia Trie
  """
  @spec construct_empty :: PoiProof.t()
  def construct_empty do
    %PoiProof{}
  end

  @doc """
    Calculates the root hash of the given Poi proof.
    Returns a hash of all zeroes for proofs for empty tries.
  """
  @spec root_hash(PoiProof.t()) :: binary()
  def root_hash(%PoiProof{root_hash: :empty}) do
    <<0::size(@state_hash_bytes)-unit(8)>>
  end

  def root_hash(%PoiProof{root_hash: root_hash}) do
    root_hash
  end

  #Returns the database handles for making changes to the poi proof
  #This will initialize the PoiDB wrapper
  #To obtain the modified database just call PoiDB.finilize()
  @spec get_proof_construction_handles(PoiProof.t()) :: Map.t()
  defp get_proof_construction_handles(%PoiProof{db: proof_db}) do
    PoiDB.prepare_for_requests(proof_db)
    %{
      get: fn _ -> :error end,
      put: &PoiDB.put/2
    }
  end

  #Returns database handles for reading the database
  #Writing to the database will fail
  @spec get_proof_readonly_handles(PoiProof.t()) :: Map.t()
  defp get_proof_readonly_handles(%PoiProof{db: proof_db}) do
    %{
      get:
        fn key ->
          case Map.get(proof_db, key) do
            nil ->
              :not_found
            value ->
              {:ok, value}
          end
        end,
      put: fn _ -> :error end
    }
  end

  @spec trie_root_hash(Trie.t()) :: :empty | binary()
  defp trie_root_hash(%Trie{} = trie) do
    case PatriciaMerkleTree.root_hash(trie) do
      @canonical_root_hash ->
        :empty
      hash ->
        hash
    end
  end

  @spec poi_root_hash_to_trie_root_hash(PoiProof.t()) :: binary()
  defp poi_root_hash_to_trie_root_hash(%PoiProof{root_hash: :empty}) do
    @canonical_root_hash
  end

  defp poi_root_hash_to_trie_root_hash(%PoiProof{root_hash: root_hash}) do
    root_hash
  end

  #Returns a trie suitable for proof construction
  @spec get_proof_construction_trie(PoiProof.t()) :: Trie.t()
  defp get_proof_construction_trie(%PoiProof{} = poi_proof) do
    len = Storage.max_rlp_len()
    Trie.new(
      ExternalDB.init(get_proof_construction_handles(poi_proof)),
      <<0::size(len)-unit(8)>> #this will avoid writing the initial root hash to the DB
    )
  end

  #Returns a trie suitable for proof verification and lookups
  @spec get_readonly_proof_trie(PoiProof.t()) :: Trie.t()
  defp get_readonly_proof_trie(%PoiProof{} = poi_proof) do
    len = Storage.max_rlp_len()
    Trie.new(
      ExternalDB.init(get_proof_readonly_handles(poi_proof)),
      <<0::size(len)-unit(8)>> #this will avoid writing the initial root hash to the readonly DB
    )
  end

  #Invokes proof construction on the Poi proof. Uses the PoiDB wrapper for obtaining imperative behaviour.
  @spec invoke_proof_construction(PoiProof.t(), Trie.t(), Trie.key()) :: {:ok, Trie.value(), Map.t()} | {:error, :key_not_found}
  defp invoke_proof_construction(%PoiProof{} = poi_proof, %Trie{} = trie, key) do
    proof_trie = get_proof_construction_trie(poi_proof)
    {value, _} = Proof.construct_proof({trie, key, proof_trie})
    new_proof_db = PoiDB.finilize()
    case value do
      nil ->
        {:error, :key_not_found}
      _ ->
        {:ok, value, new_proof_db}
    end
  end

  @doc """
    Adds the value associated with the given key in the given trie to the Poi proof
  """
  @spec add_to_poi(PoiProof.t(), Trie.t(), Trie.key()) :: {:ok, Trie.value(), PoiProof.t()} | {:error, :wrong_root_hash | :key_not_found}
  def add_to_poi(%PoiProof{root_hash: root_hash} = poi_proof, %Trie{} = trie, key) do
    case trie_root_hash(trie) do
      ^root_hash ->
        case invoke_proof_construction(poi_proof, trie, key) do
          {:error, _} = err ->
            err
          {:ok, value, proof_db} ->
            {:ok, value, %PoiProof{poi_proof | db: proof_db}}
        end
      _ ->
        {:error, :wrong_root_hash}
    end
  end

  @doc """
    Verifies if an entry is present under the given key in the Poi proof
  """
  @spec verify_poi_entry(PoiProof.t(), Trie.key, Trie.value()) :: boolean()
  def verify_poi_entry(%PoiProof{} = poi_proof, key, serialized_value) do
    root_hash = poi_root_hash_to_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.verify_proof(key, serialized_value, root_hash, proof_trie)
  end

  @doc """
    Lookups the entry assiociated with the given key in the Poi proof
  """
  @spec lookup_in_poi(PoiProof.t(), Trie.key()) :: {:ok, Trie.value()} | :error
  def lookup_in_poi(%PoiProof{} = poi_proof, key) do
    root_hash = poi_root_hash_to_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.lookup_proof(key, root_hash, proof_trie)
  end

  @doc """
    Serializes the poi proof to a list
  """
  @spec encode_to_list(PoiProof.t()) :: list()
  def encode_to_list(%PoiProof{root_hash: :empty}) do
    []
  end

  def encode_to_list(%PoiProof{root_hash: root_hash, db: db}) do
    contents =
      db
      |> Enum.map(fn {key, value} -> [key, ExRLP.decode(value)] end)
      |> Enum.sort_by(fn [key, _] -> key end) #the specification requires keys to be sorted in serialized POI's
    [[root_hash, contents]]
  end

  @doc """
    Deserialized the poi proof from a list
  """
  @spec decode_from_list(list()) :: PoiProof.t() | {:error, String.t()}
  def decode_from_list([]) do
    construct_empty()
  end

  def decode_from_list([[root_hash, contents]]) when is_binary(root_hash) and is_list(contents) do
    db =
      Enum.reduce(
        contents,
        %{},
        fn([key, value], acc) -> Map.put(acc, key, ExRLP.encode(value)) end)

    %PoiProof{root_hash: root_hash, db: db}
  end

  def decode_from_list(_) do
    {:error, "#{__MODULE__} deserialization of POI failed"}
  end
end
