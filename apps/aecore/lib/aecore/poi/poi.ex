defmodule Aecore.Poi.Poi do
  @moduledoc """
  Module implementing a Proof of Inclusion(POI) on state trees for the entire chainstate.
  The POI is an abstraction for sharing and accesing a subset of an existing chainstate to any intrested party.
  The POI is cryptographically tied to the chainstate from which the POI was generated (we can proof that the POI is a subset of a chainstate with a given state hash).
  """

  alias Aecore.Account.Account
  alias Aecore.Chain.Chainstate
  alias Aecore.Keys
  alias Aecore.Poi.Poi
  alias Aecore.Poi.PoiProof
  alias Aeutil.Hash

  @version 1
  @protocol_version_field_size 64
  @protocol_version 15

  @typedoc """
  Structure of a Poi proof for the chainstate
  """
  @type t :: %Poi{
          accounts: PoiProof.t(),
          oracles: PoiProof.t(),
          naming: PoiProof.t(),
          channels: PoiProof.t(),
          calls: PoiProof.t(),
          contracts: PoiProof.t()
        }

  @typedoc """
  Type representing the types of proofs in the poi
  """
  @type tree_type :: :accounts | :oracles | :naming | :channels | :calls | :contracts

  @doc """
  Definition of a Poi proof for the entire chainstate

  ### Parameters
  - accounts  - Poi proof for the accounts trie
  - oracles   - Poi proof for the oracles trie
  - naming    - Poi proof for the naming trie
  - channels  - Poi proof for the channels trie
  - calls     - Poi proof for the calls trie
  - contracts - Poi proof for the contracts trie
  """
  defstruct [
    :accounts,
    :oracles,
    :naming,
    :channels,
    :calls,
    :contracts
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  @doc """
  Creates a new Poi for the given chainstate
  """
  @spec construct(Chainstate.t()) :: Poi.t()
  def construct(%Chainstate{
        accounts: accounts,
        oracles: %{oracle_tree: oracles},
        naming: naming,
        channels: channels
      }) do
    %Poi{
      accounts: PoiProof.construct(accounts),
      oracles: PoiProof.construct(oracles),
      naming: PoiProof.construct(naming),
      channels: PoiProof.construct(channels),
      calls: PoiProof.construct_empty(),
      contracts: PoiProof.construct_empty()
    }
  end

  @doc """
  Calculates the root hash of the Poi
  """
  @spec calculate_root_hash(Poi.t()) :: binary()
  def calculate_root_hash(%Poi{
        accounts: accounts_proof,
        oracles: oracles_proof,
        naming: naming_proof,
        channels: channels_proof,
        calls: calls_proof,
        contracts: contracts_proof
      }) do
    [
      accounts_proof,
      oracles_proof,
      naming_proof,
      channels_proof,
      calls_proof,
      contracts_proof
    ]
    |> Enum.reduce(<<@protocol_version::size(@protocol_version_field_size)>>, fn proof, acc ->
      acc <> PoiProof.root_hash(proof)
    end)
    |> Hash.hash()
  end

  @doc """
  Adds an entry for the specified key to the Poi
  """
  @spec add_to_poi(tree_type(), Keys.pubkey(), Chainstate.t(), Poi.t()) ::
          {:ok, Poi.t()} | {:error, :wrong_root_hash | :key_not_found | :not_yet_implemented}
  def add_to_poi(
        :accounts,
        pub_key,
        %Chainstate{accounts: accounts},
        %Poi{accounts: accounts_proof} = poi
      ) do
    case PoiProof.add_to_poi(accounts_proof, accounts, pub_key) do
      {:error, _} = err ->
        err

      {:ok, _, proof} ->
        {:ok, %Poi{poi | accounts: proof}}
    end
  end

  # def add_to_poi(:contracts, _, _, _) do
  # Placeholder
  # end

  def add_to_poi(_, _, _, _) do
    # epoch currently only implemented accounts and contracts
    {:error, :not_yet_implemented}
  end

  @doc """
  Verifies whether the poi contains the given entry under the given key
  """
  @spec verify_poi?(Poi.t(), Keys.pubkey(), Account.t()) :: boolean()
  def verify_poi?(%Poi{accounts: accounts_proof}, pub_key, %Account{} = account) do
    PoiProof.verify_poi_entry(accounts_proof, pub_key, Account.rlp_encode(account))
  end

  # Placeholder
  # def verify_poi(%Poi{contracts: contracts_proof}, %Contract{})

  @doc """
  Lookups the entry associated with the given key in the Poi
  """
  @spec lookup_poi(tree_type(), Poi.t(), Keys.pubkey()) ::
          {:ok, Account.t()} | {:error, :key_not_found | String.t() | :not_yet_implemented}
  def lookup_poi(:accounts, %Poi{accounts: accounts_proof}, pub_key) do
    case PoiProof.lookup_in_poi(accounts_proof, pub_key) do
      :error ->
        {:error, :key_not_present}

      {:ok, serialized_account} ->
        # deserialization of wrong data sometimes throws an exception
        try do
          Account.rlp_decode(serialized_account)
        rescue
          _ -> {:error, "#{__MODULE__} Deserialization of account failed"}
        end
    end
  end

  # Placeholder
  # def lookup_poi(:contracts, _, _)

  def lookup_poi(_, _, _) do
    # epoch currently only implemented accounts and contracts
    {:error, :not_yet_implemented}
  end

  @doc """
  Retrieves the balance for an account included in the Poi.
  """
  @spec account_balance(Poi.t(), Keys.pubkey()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def account_balance(%Poi{} = poi, pubkey) do
    case Poi.lookup_poi(:accounts, poi, pubkey) do
      {:ok, account} ->
        {:ok, account.balance}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Serializes the Poi to a list
  """
  @spec encode_to_list(Poi.t()) :: list()
  def encode_to_list(%Poi{
        accounts: accounts_proof,
        oracles: oracles_proof,
        naming: naming_proof,
        channels: channels_proof,
        calls: calls_proof,
        contracts: contracts_proof
      }) do
    payload =
      Enum.map(
        [
          accounts_proof,
          calls_proof,
          channels_proof,
          contracts_proof,
          naming_proof,
          oracles_proof
        ],
        &PoiProof.encode_to_list/1
      )

    [:binary.encode_unsigned(@version) | payload]
  end

  @doc """
  Deserializes the Poi from a list
  """
  @spec decode_from_list(non_neg_integer(), list()) :: Poi.t() | {:error, String.t()}
  def decode_from_list(@version, [accounts, calls, channels, contracts, naming, oracles]) do
    decoded_components =
      Enum.map(
        [
          accounts: accounts,
          calls: calls,
          channels: channels,
          contracts: contracts,
          naming: naming,
          oracles: oracles
        ],
        fn {key, value} -> {key, PoiProof.decode_from_list(value)} end
      )

    errors = for {key, {:error, reason}} <- decoded_components, do: {key, reason}

    case List.first(errors) do
      nil ->
        {:ok,
         Enum.reduce(decoded_components, %Poi{}, fn {key, {:ok, value}}, acc ->
           Map.put(acc, key, value)
         end)}

      {key, reason} ->
        {:error, "#{__MODULE__}: Deserialization of key #{key} failed with reason: #{reason}"}
    end
  end

  def decode_from_list(_, _) do
    {:error, "#{__MODULE__} deserialization of POI failed"}
  end
end
