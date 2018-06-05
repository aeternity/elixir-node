defmodule Aecore.Keys.Peer do
  @moduledoc """
    Module for working with Peer keys
  """

  alias Aewallet.Cypher
  alias Aecore.Keys.Utils
  alias Aecore.Keys.Worker, as: Keys
  alias Aeutil.Bits

  @type pubkey :: binary()

  @type privkey :: binary()

  @type t :: {pubkey(), privkey()}

  @doc """
  Gets the default dir for storing the wallet
  """
  @spec keypair_dir() :: String.t()
  def keypair_dir do
    Application.get_env(:aecore, :peer_keys)[:path]
  end

  def keypair do
    Keys.get_peer_keypair()
  end

  @spec create_keypair() :: :ok | {:error, String.t()}
  def create_keypair do
    case keypair_dir()
         |> File.mkdir()
         |> Utils.has_dir?(keypair_dir()) do
      :ok ->
        :ok

      {:error, :empty} ->
        keypair = generate_keypair()

        case check_keypair(keypair) do
          true ->
            keypair
            |> encrypt_keypair(Utils.password())
            |> save_keypair(keypair_dir())

          false ->
            {:error, "#{__MODULE__} Derivation of Peer keypair failed"}
        end

      err ->
        err
    end
  end

  def generate_keypair do
    %{public: sign_pub, secret: sign_sec} = :enacl.sign_keypair()
    pubkey = :enacl.crypto_sign_ed25519_public_to_curve25519(sign_pub)
    privkey = :enacl.crypto_sign_ed25519_secret_to_curve25519(sign_sec)
    pubkey <> privkey
  end

  def load_keypair do
    case File.ls(keypair_dir()) do
      {:ok, [file_name]} ->
        keypair =
          keypair_dir()
          |> Kernel.<>("/")
          |> Kernel.<>(file_name)
          |> File.read()
          |> Utils.read_file()
          |> decrypt_keypair(Utils.password())

        <<pubkey::binary-32, privkey::binary>> = keypair
        {pubkey, privkey}

      err ->
        err
    end
  end

  def check_keypair(<<pubkey::binary-32, privkey::binary>>) do
    pubkey == :enacl.curve25519_scalarmult_base(privkey)
  end

  def encrypt_keypair(keypair, password) do
    Cypher.encrypt(keypair, password)
  end

  def decrypt_keypair({:ok, encrypted_keys}, password) do
    Cypher.decrypt(encrypted_keys, password)
  end

  def save_keypair(encrypted_keypair, path) do
    {{year, month, day}, {hours, minutes, seconds}} = :calendar.local_time()
    file_name = "peer_keypair--#{year}-#{month}-#{day}-#{hours}-#{minutes}-#{seconds}"

    file_path = Path.join(path, file_name)

    case File.open(file_path, [:write]) do
      {:ok, file} ->
        IO.binwrite(file, encrypted_keypair)
        File.close(file)
        :ok

      {:error, message} ->
        {:error, "The path you have given has thrown an #{message} error!"}
    end
  end

  def base58c_encode(bin) do
    Bits.encode58c("pp", bin)
  end

  def base58c_decode(<<"pp$", payload::binary>>) do
    Bits.decode58(payload)
  end
end
