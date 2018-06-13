defmodule Aecore.Wallet.Worker do
  @moduledoc """
  Module for handling the creation of a Wallet file
  """

  use GenServer

  alias Aewallet.Wallet
  alias Aewallet.KeyPair

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
    GenServer.start_link(__MODULE__, %{pubkey: nil}, name: __MODULE__)
  end

  def init(state) do
    case get_aewallet_dir()
         |> File.mkdir()
         |> has_wallet(get_aewallet_dir()) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        {:stop, "Failed due to #{reason} error.."}
    end
  end

  @doc """
  Gets the default dir for storing the wallet
  """
  @spec get_aewallet_dir() :: String.t()
  def get_aewallet_dir do
    Application.get_env(:aecore, :aewallet)[:path]
  end

  @spec get_pub_key_size :: non_neg_integer()
  def get_pub_key_size do
    Application.get_env(:aecore, :aewallet)[:pub_key_size]
  end

  @spec key_size_valid?(pub_key :: binary()) :: boolean()
  def key_size_valid?(pub_key) do
    byte_size(pub_key) == get_pub_key_size()
  end

  @doc """
  Gets the default password for the dafault wallet
  """
  @spec get_aewallet_pass() :: String.t()
  def get_aewallet_pass do
    Application.get_env(:aecore, :aewallet)[:pass]
  end

  @spec get_public_key() :: binary()
  def get_public_key do
    get_public_key("")
  end

  @spec get_public_key(String.t()) :: binary()
  def get_public_key(derivation_path) do
    get_public_key(derivation_path, get_aewallet_pass())
  end

  @spec get_public_key(String.t(), String.t()) :: binary()
  def get_public_key(derivation_path, password) do
    get_public_key(derivation_path, password, :mainnet)
  end

  @spec get_public_key(String.t(), String.t(), opts()) :: binary()
  def get_public_key(derivation_path, password, network) do
    GenServer.call(__MODULE__, {:get_pub_key, {derivation_path, password, network}})
  end

  @spec get_private_key() :: binary()
  def get_private_key do
    get_private_key("")
  end

  @spec get_private_key(String.t()) :: binary()
  def get_private_key(derivation_path) do
    get_private_key(derivation_path, get_aewallet_pass())
  end

  @spec get_private_key(String.t(), String.t()) :: binary()
  def get_private_key(derivation_path, password) do
    get_private_key(derivation_path, password, :mainnet)
  end

  @spec get_private_key(String.t(), String.t(), opts()) :: binary()
  def get_private_key(derivation_path, password, network) do
    GenServer.call(__MODULE__, {:get_priv_key, {derivation_path, password, network}})
  end

  @spec to_public_key(privkey()) :: pubkey()
  def to_public_key(priv_key) when byte_size(priv_key) == 32 do
    priv_key
    |> KeyPair.generate_pub_key()
    |> KeyPair.compress()
  end

  ## Server Callbacks

  def handle_call(
        {:get_pub_key, {derivation_path, password, network}},
        _from,
        %{pubkey: nil} = state
      ) do
    pub_key =
      if derivation_path == "" do
        {:ok, pub_key} =
          get_aewallet_dir()
          |> get_file_name()
          |> Wallet.get_public_key(password, network: network)

        pub_key
      else
        key = derive_key(derivation_path, password)
        KeyPair.compress(key.key)
      end

    pub_key_state =
      if derivation_path == "" do
        pub_key
      else
        nil
      end

    {:reply, pub_key, %{state | pubkey: pub_key_state}}
  end

  def handle_call(
        {:get_pub_key, {derivation_path, password, _network}},
        _from,
        %{pubkey: pub_key} = state
      ) do
    pub_key =
      if derivation_path == "" do
        pub_key
      else
        key = derive_key(derivation_path, password)
        KeyPair.compress(key.key)
      end

    {:reply, pub_key, state}
  end

  def handle_call({:get_priv_key, {derivation_path, password, network}}, _from, state) do
    priv_key =
      if derivation_path == "" do
        {:ok, priv_key} =
          get_aewallet_dir()
          |> get_file_name()
          |> Wallet.get_private_key(password, network: network)

        priv_key
      else
        key = derive_key(derivation_path, password)
        key.key
      end

    {:reply, priv_key, state}
  end

  ## Inner functions

  @spec derive_key(String.t(), String.t()) :: map()
  defp derive_key(derivation_path, password) do
    password
    |> get_seed()
    |> KeyPair.generate_master_key()
    |> KeyPair.derive(derivation_path)
  end

  @spec get_seed(String.t()) :: binary()
  defp get_seed(password) do
    {:ok, seed} =
      get_aewallet_dir()
      |> get_file_name()
      |> Wallet.get_seed(password)

    seed
  end

  @spec has_wallet(:ok, String.t()) :: :ok
  defp has_wallet(:ok, path), do: create_wallet(path)

  @spec has_wallet(tuple(), String.t()) :: :ok
  defp has_wallet({:error, :eexist}, path) do
    case get_file_name(path) do
      [] -> create_wallet(path)
      [_] -> :ok
    end
  end

  @spec has_wallet(tuple(), String.t()) :: {:error, String.t()}
  defp has_wallet({:error, reason}, _path) do
    {:error, reason}
  end

  @spec create_wallet(String.t()) :: :ok
  defp create_wallet(path) do
    {:ok, _mnemonic, _path, _wallet_type} = Wallet.create_wallet(get_aewallet_pass(), path)
    :ok
  end

  @spec get_file_name(String.t()) :: list()
  defp get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard()
  end
end
