defmodule Aecore.Keys.Worker do
  @moduledoc """
  Module for handling the creation of a Wallet file
  """

  use GenServer

  alias Aewallet.Wallet, as: Aewallet
  alias Aewallet.KeyPair
  alias Aecore.Keys.Wallet
  alias Aecore.Keys.Peers
  alias Aecore.Keys.Utils

  @typedoc "Public key representing an account"
  @type pubkey() :: binary()

  @typedoc "Private key of the account"
  @type privkey() :: binary()

  @typedoc "Wallet type"
  @type wallet_type :: :ae | :btc

  @typedoc "Options for network"
  @type opts :: :mainnet | :testnet

  ## Client API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{wallet_pubkey: nil, peer_keys: nil}, name: __MODULE__)
  end

  def init(state) do
    with :ok <- Wallet.get_wallet(),
         :ok <- Peers.create_keypair() do
      {:ok, state}
    else
      {:error, reason} ->
        {:stop, "Failed due to #{reason} error.."}
    end
  end

  @spec get_peer_keypair() :: Peers.t()
  def get_peer_keypair do
    GenServer.call(__MODULE__, :get_peer_keys)
  end

  @spec get_wallet_pubkey(String.t(), String.t(), opts()) :: binary()
  def get_wallet_pubkey(derivation_path, password, network) do
    GenServer.call(__MODULE__, {:get_wallet_pubkey, {derivation_path, password, network}})
  end

  @spec get_wallet_privkey(String.t(), String.t(), opts()) :: binary()
  def get_wallet_privkey(derivation_path, password, network) do
    GenServer.call(__MODULE__, {:get_wallet_privkey, {derivation_path, password, network}})
  end

  ## Server Callbacks

  def handle_call(:get_peer_keys, _from, %{peer_keys: nil} = state) do
    keypair = Peers.load_keypair()
    # %{state | peer_keys: keypair}}
    {:reply, keypair, state}
  end

  def handle_call(:get_peer_keys, _from, %{peer_keys: keys} = state) do
    {:reply, keys, state}
  end

  def handle_call(
        {:get_wallet_pubkey, {derivation_path, password, network}},
        _from,
        %{wallet_pubkey: nil} = state
      ) do
    pub_key =
      if derivation_path == "" do
        {:ok, pub_key} =
          Wallet.aewallet_dir()
          |> Utils.get_file_name()
          |> Aewallet.get_public_key(password, network: network)

        pub_key
      else
        key = Wallet.derive_key(derivation_path, password)
        KeyPair.compress(key.key)
      end

    pub_key_state =
      if derivation_path == "" do
        pub_key
      else
        nil
      end

    {:reply, pub_key, %{state | wallet_pubkey: pub_key_state}}
  end

  def handle_call(
        {:get_wallet_pubkey, {derivation_path, password, _network}},
        _from,
        %{wallet_pubkey: pub_key} = state
      ) do
    pub_key =
      if derivation_path == "" do
        pub_key
      else
        key = Wallet.derive_key(derivation_path, password)
        KeyPair.compress(key.key)
      end

    {:reply, pub_key, state}
  end

  def handle_call({:get_wallet_privkey, {derivation_path, password, network}}, _from, state) do
    priv_key =
      if derivation_path == "" do
        {:ok, priv_key} =
          Wallet.aewallet_dir()
          |> Utils.get_file_name()
          |> Aewallet.get_private_key(password, network: network)

        priv_key
      else
        key = Wallet.derive_key(derivation_path, password)
        key.key
      end

    {:reply, priv_key, state}
  end
end
