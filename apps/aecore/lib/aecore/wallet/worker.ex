defmodule Aecore.Wallet.Worker do
  @defmodule """
  Module for handling the creation of a Wallet file
  """

  use GenServer

  @aewallet_dir Application.get_env(:aecore, :aewallet)[:path]
  @aewallet_pass "1234"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{path: @aewallet_dir}, name: __MODULE__)
  end

  def init(%{path: path} = state) do
    has_wallet(File.exists?(path))
    {:ok, state}
  end

  @spec get_public_key(String.t()) :: binary()
  def get_public_key(password) do
    GenServer.call(__MODULE__, {:get_pub_key, password})
  end

  @spec get_private_key(String.t()) :: binary()
  def get_private_key(password) do
    GenServer.call(__MODULE__, {:get_priv_key, password})
  end

  def handle_call({:get_pub_key, password}, _from, %{path: path} = state) do
    {:ok, pub_key} =
      Aewallet.Wallet.get_public_key(get_file_name(path), password)
    {:reply, pub_key, state}
  end

  def handle_call({:get_priv_key, password}, _from, %{path: path} = state) do
    {:ok, priv_key} =
      Aewallet.Wallet.get_private_key(get_file_name(path), password)
    {:reply, priv_key, state}
  end

  ## Inner functions

  defp has_wallet(true) do
    case get_file_name(@aewallet_dir) do
      [ ] -> create_wallet(@aewallet_dir)
      [_] -> :ok
    end
  end
  defp has_wallet(false) do
    if File.mkdir @aewallet_dir do
      create_wallet(@aewallet_dir)
    else
      throw("Failed creating the wallet dir: #{@aewallet_dir}")
    end
  end

  defp create_wallet(path) do
    IO.inspect "Creating a wallet"
    Aewallet.Wallet.create_wallet(@aewallet_pass, "", path)
  end

  defp get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard()
  end
end
