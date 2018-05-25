defmodule Aecore.Keys.Wallet do
  @moduledoc """
  API for calling the wallet keypair functions
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Keys.Utils
  alias Aewallet.Wallet, as: AeternityWallet
  alias Aewallet.KeyPair

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
    case aewallet_dir()
         |> File.mkdir()
         |> Utils.has_dir?(aewallet_dir()) do
      :ok ->
        :ok

      {:error, :empty} ->
        create_wallet(aewallet_dir())

      err ->
        err
    end
  end

  @doc """
  Gets the default dir for storing the wallet
  """
  @spec aewallet_dir() :: String.t()
  def aewallet_dir do
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

  @spec to_public_key(privkey()) :: pubkey()
  def to_public_key(priv_key) when byte_size(priv_key) == 32 do
    priv_key
    |> KeyPair.generate_pub_key()
    |> KeyPair.compress()
  end

  @doc """
  Derives the key for the given path
  """
  @spec derive_key(String.t(), String.t()) :: map()
  def derive_key(derivation_path, password) do
    password
    |> get_seed()
    |> KeyPair.generate_master_key()
    |> KeyPair.derive(derivation_path)
  end

  @spec get_seed(String.t()) :: binary()
  def get_seed(password) do
    {:ok, seed} =
      aewallet_dir()
      |> Utils.get_file_name()
      |> AeternityWallet.get_seed(password)

    seed
  end

  @spec create_wallet(String.t()) :: :ok
  defp create_wallet(path) do
    {:ok, _mnemonic, _path, _wallet_type} =
      AeternityWallet.create_wallet(get_aewallet_pass(), path)

    :ok
  end
end
