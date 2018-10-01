defmodule Aecore.Poi.PoiProof do
  @moduledoc """
  Implements a Proof Of Inclusion(POI) for a single Merkle Patricia Trie. This module is type agnostic, any keys or values passed to this module must be serialized beforehand. This is an abstraction layer for providing a view into a subset of a given merkle patricia trie. The POI is cryptographicaly tied to the original merkle patricia tree - we can cryptographicly proof that the POI was generated from a merkle patricia trie with a given root hash.

  Standard merkle patricia tries rely on a persistent key value store which is accesed by callbacks. This module uses a in memory map as the key value store and uses the PoiPersistence wrapper in order to encapsulate the side effects of the PatriciaMerkleTree module.
  """

  alias Aecore.Poi.PoiPersistence
  alias Aecore.Poi.PoiProof
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Trie.Storage
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB

  # This is the canonical root hash of an empty Patricia merkle tree
  @canonical_root_hash <<69, 176, 207, 194, 32, 206, 236, 91, 124, 28, 98, 196, 212, 25, 61, 56,
                         228, 235, 164, 142, 136, 21, 114, 156, 231, 95, 156, 10, 176, 228, 193,
                         192>>

  @state_hash_bytes 32

  @typedoc """
  Type of state hash used by the Merkle Patricia Trie library
  """
  @type state_hash :: binary()

  @typedoc """
  Type of the state hash used by this module
  """
  @type internal_state_hash :: :empty | state_hash()

  @typedoc """
  Structure of a Poi proof for a single trie
  """
  @type t :: %PoiProof{
          root_hash: internal_state_hash(),
          db: map()
        }

  @doc """
  Definition of a Poi proof for a single trie

  ### Parameters
  - root_hash - contains the root hash of the associated merkle patricia trie
  - db -        contains the proof database. Any changes to this database via the PatriciaMerkleTree library
                must be made via the ProofDB wrapper
  """
  defstruct root_hash: :empty,
            db: %{}

  @doc """
  Creates a new Poi proof for a single Merkle Patricia Trie
  """
  @spec construct(Trie.t()) :: PoiProof.t()
  def construct(%Trie{} = trie) do
    %PoiProof{
      root_hash: patricia_merkle_trie_root_hash_to_internal_root_hash(trie)
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
  @spec root_hash(PoiProof.t()) :: state_hash()
  def root_hash(%PoiProof{root_hash: :empty}) do
    <<0::size(@state_hash_bytes)-unit(8)>>
  end

  def root_hash(%PoiProof{root_hash: root_hash}) do
    root_hash
  end

  # Returns the database handles for making changes to the poi proof
  # This will initialize the PoiPersistence wrapper
  # To obtain the modified database just call PoiPersistence.finalize()
  @spec get_proof_database_write_only_callbacks(PoiProof.t()) :: map()
  defp get_proof_database_write_only_callbacks(%PoiProof{db: proof_db}) do
    PoiPersistence.prepare_for_requests(proof_db)

    %{
      get: fn _ -> :error end,
      put: &PoiPersistence.put/2
    }
  end

  # Returns database handles for reading the database
  # Writing to the database will fail
  @spec get_proof_database_readonly_callbacks(PoiProof.t()) :: map()
  defp get_proof_database_readonly_callbacks(%PoiProof{db: proof_db}) do
    %{
      get: fn key ->
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

  @spec patricia_merkle_trie_root_hash_to_internal_root_hash(Trie.t()) :: internal_state_hash()
  defp patricia_merkle_trie_root_hash_to_internal_root_hash(%Trie{} = trie) do
    case PatriciaMerkleTree.root_hash(trie) do
      @canonical_root_hash ->
        :empty

      hash ->
        hash
    end
  end

  @spec patricia_merkle_trie_root_hash(PoiProof.t()) :: state_hash()
  defp patricia_merkle_trie_root_hash(%PoiProof{root_hash: :empty}) do
    @canonical_root_hash
  end

  defp patricia_merkle_trie_root_hash(%PoiProof{root_hash: root_hash}) do
    root_hash
  end

  # Returns a trie suitable for proof construction
  @spec get_proof_construction_trie(PoiProof.t()) :: Trie.t()
  defp get_proof_construction_trie(%PoiProof{} = poi_proof) do
    len = Storage.max_rlp_len()

    Trie.new(
      ExternalDB.init(get_proof_database_write_only_callbacks(poi_proof)),
      # this will avoid writing the initial root hash to the DB
      <<0::size(len)-unit(8)>>
    )
  end

  # Returns a trie suitable for proof verification and lookups
  @spec get_readonly_proof_trie(PoiProof.t()) :: Trie.t()
  defp get_readonly_proof_trie(%PoiProof{} = poi_proof) do
    len = Storage.max_rlp_len()

    Trie.new(
      ExternalDB.init(get_proof_database_readonly_callbacks(poi_proof)),
      # this will avoid writing the initial root hash to the readonly DB
      <<0::size(len)-unit(8)>>
    )
  end

  # Wrapper for proof construction on merkle patricia trees. Uses the PoiPersistence wrapper for obtaining functional behaviour although the underlaying library relies on side effects in order to achieve persistence.
  @spec side_efects_encapsulating_proof_construction(PoiProof.t(), Trie.t(), Trie.key()) ::
          {:ok, Trie.value(), map()} | {:error, :key_not_found}
  defp side_efects_encapsulating_proof_construction(%PoiProof{} = poi_proof, %Trie{} = trie, key) do
    proof_trie = get_proof_construction_trie(poi_proof)
    {value, _} = Proof.construct_proof({trie, key, proof_trie})
    new_proof_db = PoiPersistence.finalize()

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
  @spec add_to_poi(PoiProof.t(), Trie.t(), Trie.key()) ::
          {:ok, Trie.value(), PoiProof.t()} | {:error, :wrong_root_hash | :key_not_found}
  def add_to_poi(%PoiProof{root_hash: root_hash} = poi_proof, %Trie{} = trie, key) do
    with ^root_hash <- patricia_merkle_trie_root_hash_to_internal_root_hash(trie),
         {:ok, value, proof_db} <-
           side_efects_encapsulating_proof_construction(poi_proof, trie, key) do
      {:ok, value, %PoiProof{poi_proof | db: proof_db}}
    else
      h when is_binary(h) or h === :empty ->
        {:error, :wrong_root_hash}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Verifies if an entry is present under the given key in the Poi proof
  """
  @spec verify_poi_entry(PoiProof.t(), Trie.key(), Trie.value()) :: boolean()
  def verify_poi_entry(%PoiProof{} = poi_proof, key, serialized_value) do
    root_hash = patricia_merkle_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.verify_proof?(key, serialized_value, root_hash, proof_trie)
  end

  @doc """
  Lookups the entry assiociated with the given key in the Poi proof
  """
  @spec lookup_in_poi(PoiProof.t(), Trie.key()) :: {:ok, Trie.value()} | :error
  def lookup_in_poi(%PoiProof{} = poi_proof, key) do
    root_hash = patricia_merkle_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.lookup_proof(key, root_hash, proof_trie)
  end

  @doc """
  Serializes the poi proof to a list
  """
  @spec encode_to_list(PoiProof.t()) :: list(list(binary()))
  def encode_to_list(%PoiProof{root_hash: :empty}) do
    []
  end

  def encode_to_list(%PoiProof{root_hash: root_hash, db: db}) do
    contents =
      db
      |> Enum.map(fn {key, value} -> [key, ExRLP.decode(value)] end)
      # the specification requires keys to be sorted in serialized POI's
      |> Enum.sort_by(fn [key, _] -> key end)

    [[root_hash, contents]]
  end

  @doc """
  Deserialized the poi proof from a list
  """
  @spec decode_from_list(list(list(binary()))) :: {:ok, PoiProof.t()} | {:error, String.t()}
  def decode_from_list([]) do
    {:ok, construct_empty()}
  end

  def decode_from_list([[root_hash, contents]]) when is_binary(root_hash) and is_list(contents) do
    db =
      Enum.reduce(contents, %{}, fn [key, value], acc ->
        Map.put(acc, key, ExRLP.encode(value))
      end)

    {:ok, %PoiProof{root_hash: root_hash, db: db}}
  end

  def decode_from_list(_) do
    {:error, "#{__MODULE__} deserialization of POI failed"}
  end
end
