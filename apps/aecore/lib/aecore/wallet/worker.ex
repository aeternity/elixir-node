defmodule Aecore.Wallet.Worker do
  @defmodule """
  Module for handling the creation of a Wallet file
  """

  use GenServer

  alias Aewallet.Wallet

  @typedoc "Options for network"
  @type opts :: :mainnet | :testnet

  @aewallet_dir Application.get_env(:aecore, :aewallet)[:path]
  @aewallet_pass Application.get_env(:aecore, :aewallet)[:pass]

  ## Client API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{path: @aewallet_dir, pubkey: nil}, name: __MODULE__)
  end

  def init(%{path: path} = state) do
    :ok = path
    |> File.mkdir()
    |> has_wallet(path)

    {:ok, state}
  end

  @spec get_public_key(String.t()) :: binary()
  def get_public_key(password) do
    GenServer.call(__MODULE__, {:get_pub_key, {password, :mainnet}})
  end

  @spec get_public_key(String.t(), opts()) :: binary()
  def get_public_key(password, network) do
    GenServer.call(__MODULE__, {:get_pub_key, {password, network}})
  end

  @spec get_private_key(String.t()) :: binary()
  def get_private_key(password) do
    GenServer.call(__MODULE__, {:get_priv_key, {password, :mainnet}})
  end

  @spec get_private_key(String.t(), opts()) :: binary()
  def get_private_key(password, network) do
    GenServer.call(__MODULE__, {:get_priv_key, {password, network}})
  end

  ## Server Callbacks

  def handle_call({:get_pub_key, {password, network}}, _from, %{pubkey: nil} = state) do
    {:ok, pub_key, _} =
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

  ## Inner functions

  defp has_wallet(:ok, path), do: create_wallet(path)
  defp has_wallet({:error, :eexist}, path) do
    case get_file_name(path) do
      []  -> create_wallet(path)
      [_] -> :ok
    end
  end
  defp has_wallet({:error, reason}, _path) do
    throw("Failed due to #{reason} error..")
  end

  defp create_wallet(path) do
    {:ok, _mnemonic, _path, _wallet_type} =
      Wallet.create_wallet(@aewallet_pass, path)
    :ok
  end

  defp get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard
  end
end
