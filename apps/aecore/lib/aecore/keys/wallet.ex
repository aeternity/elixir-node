defmodule Aecore.Keys.Wallet do
  @moduledoc """
  API for calling the wallet keypair functions
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aewallet.Wallet, as: Aewallet
  alias Aewallet.KeyPair, as: AA

  @typedoc "Public key representing an account"
  @type pubkey() :: binary()

  @typedoc "Private key of the account"
  @type privkey() :: binary()

  @typedoc "Wallet type"
  @type wallet_type :: :ae | :btc

  @typedoc "Options for network"
  @type opts :: :mainnet | :testnet

  @doc """
  Gets the stored wallet keypair or creates a new one
  """
  @spec get_wallet() :: :ok | {:error, String.t()}
  def get_wallet do
    get_aewallet_dir()
    |> File.mkdir()
    |> has_wallet(get_aewallet_dir())
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
    if byte_size(pub_key) == get_pub_key_size() do
      :ok
    else
      {:error, "#{__MODULE__}: The key size is not correct, should be 33 bytes."}
    end
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
    Keys.get_wallet_pubkey(derivation_path, password, network)
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
    Keys.get_wallet_privkey(derivation_path, password, network)
  end

  @doc """
  Derives the key for the given path
  """
  @spec derive_key(String.t(), String.t()) :: map()
  def derive_key(derivation_path, password) do
    password
    |> get_seed()
    |> AA.generate_master_key()
    |> AA.derive(derivation_path)
  end

  @spec get_seed(String.t()) :: binary()
  def get_seed(password) do
    {:ok, seed} =
      get_aewallet_dir()
      |> get_file_name()
      |> Aewallet.get_seed(password)

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
    {:ok, _mnemonic, _path, _wallet_type} = Aewallet.create_wallet(get_aewallet_pass(), path)
    :ok
  end

  @spec get_file_name(String.t()) :: List.t()
  def get_file_name(path) do
    path
    |> Path.join("*/")
    |> Path.wildcard()
  end
end
