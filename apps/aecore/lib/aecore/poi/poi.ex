defmodule Aecore.Poi do

  alias Aecore.Poi
  alias Aecore.Poi.PoiProof
  alias Aecore.Chain.Chainstate
  alias Aeutil.Hash
  alias Aecore.Keys
  alias Aecore.Account.Account

  @protocol_version_field_size 64
  @protocol_version 15

  @type t :: %Poi{
          accounts: PoiProof.t(),
          oracles: PoiProof.t(),
          naming: PoiProof.t(),
          channels: PoiProof.t(),
          calls: PoiProof.t(),
          contracts: PoiProof.t()
        }

  defstruct [
    :accounts,
    :oracles,
    :naming,
    :channels,
    :calls,
    :contracts,
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  @spec construct(Chainstate.t()) :: Poi.t()
  def construct(%Chainstate{
    accounts: accounts,
    oracles: %{oracle_tree: oracles},
    naming: naming,
    channels: channels
  }) do
    %Poi{
      accounts:  PoiProof.construct(accounts),
      oracles:   PoiProof.construct(oracles),
      naming:    PoiProof.construct(naming),
      channels:  PoiProof.construct(channels),
      calls:     PoiProof.construct_empty(),
      contracts: PoiProof.construct_empty()
    }
  end

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
      acc <> PoiProof.root_hash(proof) end)
    |> Hash.hash_blake2b()
  end

  @type tree_type :: :accounts | :oracles | :naming | :channels | :calls | :contracts

  @spec add_to_poi(tree_type(), Keys.pubkey(), Chainstate.t(), Poi.t()) :: {:ok, Poi.t()} | {:error, :wrong_root_hash | :key_not_found | :nyi}
  def add_to_poi(:accounts, pub_key, %Chainstate{accounts: accounts}, %Poi{accounts: accounts_proof} = poi) do
    case PoiProof.add_to_poi(accounts_proof, accounts, pub_key) do
      {:error, _} = err ->
        err
      {:ok, _, proof} ->
        {:ok, %Poi{poi | accounts: proof}}
    end
  end

  #def add_to_poi(:contracts, _, _, _) do
    # Placeholder until PR-#526 gets merged into master
  #end

  def add_to_poi(_, _, _, _) do
    # epoch currently only implemented accounts and contracts
    {:error, :nyi}
  end

  @spec verify_poi(Poi.t(), Keys.pubkey(), Account.t()) :: boolean()
  def verify_poi(%Poi{accounts: accounts_proof}, pub_key, %Account{} = account) do
    PoiProof.verify_poi_entry(accounts_proof, pub_key, Account.rlp_encode(account))
  end

  #Placeholder until PR-#526 gets merged into master
  #def verify_poi(%Poi{contracts: contracts_proof}, %Contract{})

  @spec lookup_poi(tree_type(), Poi.t(), Keys.pubkey()) :: {:ok, Account.t()} || {:error, :key_not_present | String.t() | :nyi}
  def lookup_poi(:accounts, %Poi{accounts: accounts_proof}, pub_key) do
    case PoiProof.lookup_in_poi(accounts_proof, pub_key) do
      :error ->
        {:error, :key_not_present}
      {:ok, serialized_account} ->
        #deserialization of wrong data sometimes throws an exception
        try do
          Account.rlp_decode(serialized_account)
        rescue
          _ -> {:error, "#{__MODULE__} Deserialization of account failed"}
    end
  end

  #Placeholder until PR-#526 gets merged into master
  #def lookup_poi(:contracts, _, _)

  def lookup_poi(_, _, _) do
      # epoch currently only implemented accounts and contracts
      {:error, :nyi}
  end


end
