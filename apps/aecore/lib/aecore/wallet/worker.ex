defmodule Aecore.Wallet.Worker do
  @defmodule """
  Module for handling the creation of a Wallet file
  """

  use GenServer

  alias Aewallet.Wallet
  alias Aewallet.Encoding

  @typedoc "Options for network"
  @type opts :: :mainnet | :testnet

  ## Client API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{path: get_aewallet_dir(), pubkey: nil}, name: __MODULE__)
  end

  def init(%{path: path} = state) do
    :ok = path
    |> File.mkdir()
    |> has_wallet(path)

    {:ok, state}
  end

  @doc """
  Gets the default dir for storing the wallet
  """
  @spec get_aewallet_dir() :: String.t()
  def get_aewallet_dir do
    Application.get_env(:aecore, :aewallet)[:path]
  end

  @doc """
  Gets the default password for the dafault wallet
  """
  @spec get_aewallet_pass() :: String.t()
  def get_aewallet_pass do
    Application.get_env(:aecore, :aewallet)[:pass]
  end

  @spec get_public_key() :: binary()
  def get_public_key() do
    get_public_key(get_aewallet_pass())
  end

  @spec get_public_key(String.t()) :: binary()
  def get_public_key(password) do
    get_public_key(password, :mainnet)
  end

  @spec get_public_key(String.t(), opts()) :: binary()
  def get_public_key(password, network) do
    GenServer.call(__MODULE__, {:get_pub_key, {password, network}})
  end

  @spec get_private_key() :: binary()
  def get_private_key() do
    get_private_key(get_aewallet_pass())
  end

  @spec get_private_key(String.t()) :: binary()
  def get_private_key(password) do
    get_private_key(password, :mainnet)
  end

  @spec get_private_key(String.t(), opts()) :: binary()
  def get_private_key(password, network) do
    GenServer.call(__MODULE__, {:get_priv_key, {password, network}})
  end

  def encode(pub_key, :ae) do
    GenServer.call(__MODULE__, {:bech32_encode, {pub_key, :ae}})
  end

  def encode(pub_key, :btc) do
    GenServer.call(__MODULE__, {:bech32_encode, {pub_key, :btc}})
  end

  def decode(formatted_key) do
    GenServer.call(__MODULE__, {:bech32_decode, formatted_key})
  end

  ## Server Callbacks

  def handle_call({:get_pub_key, {password, network}}, _from, %{pubkey: nil} = state) do
    {:ok, pub_key} =
      Wallet.get_public_key(get_file_name(state.path), password, network: network)
    {:reply, pub_key, %{state | pubkey: pub_key}}
  end

  def handle_call({:get_pub_key, {password, network}}, _from, %{pubkey: key} = state) do
    {:reply, key, state}
  end

  def handle_call({:get_priv_key, {password, network}}, _from, %{path: path} = state) do
    {:ok, priv_key} =
      Wallet.get_private_key(get_file_name(path), password, network: network)
    {:reply, priv_key, state}
  end

  def handle_call({:bech32_encode, {pub_key, prefix}}, _from, state) do
    formatted_key = Encoding.encode(pub_key, prefix)
    {:reply, formatted_key, state}
  end

  def handle_call({:bech32_decode, formatted_key}, _from, state) do
    {:ok, pub_key} = Encoding.decode(formatted_key)
    {:reply, pub_key, state}
  end

  ## Inner functions

  @spec has_wallet(:ok, String.t()) :: :ok
  defp has_wallet(:ok, path), do: create_wallet(path)

  @spec has_wallet(tuple(), String.t()) :: :ok
  defp has_wallet({:error, :eexist}, path) do
    case get_file_name(path) do
      []  -> create_wallet(path)
      [_] -> :ok
    end
  end
  defp has_wallet({:error, reason}, _path) do
    throw("Failed due to #{reason} error..")
  end

  @spec create_wallet(String.t()) :: :ok
  defp create_wallet(path) do
    {:ok, _mnemonic, _path, _wallet_type} =
      Wallet.create_wallet(get_aewallet_pass(), path)
    :ok
  end

  @spec get_file_name(String.t()) :: List.t()
  defp get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard
  end
end
