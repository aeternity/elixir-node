defmodule Aecore.Keys.Worker do
  @moduledoc """
  Module for handling the Wallet (signing) keys and Peer keys.
  Keys are created on first run of the project and saved in respective dirs.
  Public sign key and Peer keys are kept in GenServer state.
  Sign privkey is always loaded/decrypted from it's local file for security.
  """

  use GenServer

  alias Aeutil.Bits

  @typedoc "Public key for signing or for peers - 32 bytes in size"
  @type pubkey :: binary()

  @typedoc "Private key for signing - 64 bytes in size"
  @type sign_priv_key :: binary()

  @typedoc "Private key for peers - 32 bytes in size"
  @type peer_priv_key :: binary()

  @pub_size 32
  @priv_sign_size 64
  @priv_peer_size 32

  @peer_key_encode "pp"
  @peer_key_decode "pp$"

  @filename_sign_pub "sign_key.pub"
  @filename_sign_priv "sign_key"

  @filename_peer_pub "peer_key.pub"
  @filename_peer_priv "peer_key"

  def start_link(_args) do
    GenServer.start_link(
      __MODULE__,
      %{sign_pubkey: <<>>, sign_priv_file: <<>>, peer_pubkey: <<>>, peer_privkey: <<>>},
      name: __MODULE__
    )
  end

  def init(_state) do
    with {:ok, sign_pubkey, sign_priv_file} <- setup_sign_keys(pwd(:sign), dir(:sign)),
         {:ok, peer_pubkey, peer_privkey} <- setup_peer_keys(pwd(:peer), dir(:peer)) do
      {:ok,
       %{
         sign_pubkey: sign_pubkey,
         sign_priv_file: sign_priv_file,
         peer_pubkey: peer_pubkey,
         peer_privkey: peer_privkey
       }}
    else
      _ ->
        ## Check this! Here we should crash maybe.
        {:stop, :reason}
    end
  end

  @doc """
  Returns the public key for signing
  """
  @spec sign_pubkey() :: pubkey()
  def sign_pubkey do
    GenServer.call(__MODULE__, :sign_pubkey)
  end

  @doc """
  Returns the private key for signing.
  """
  @spec sign_privkey() :: sign_priv_key()
  def sign_privkey do
    GenServer.call(__MODULE__, :sign_privkey)
  end

  @doc """
  Returns the public key for Nodes peer communication
  """
  @spec peer_keypair() :: {pubkey(), peer_priv_key()}
  def peer_keypair do
    GenServer.call(__MODULE__, :peer_keypair)
  end

  @doc """
  Returns encoded version of a Peer key, public or private
  """
  @spec peer_encode(pubkey() | peer_priv_key()) :: binary()
  def peer_encode(key) do
    Bits.encode58c(@peer_key_encode, key)
  end

  @doc """
  Returns decoded version of a Peer key, public or private
  """
  @spec peer_decode(binary()) :: pubkey() | peer_priv_key()
  def peer_decode(<<@peer_key_decode, payload::binary>>) do
    Bits.decode58(payload)
  end

  @doc """
  Returns a signed version of the given binary
  """
  @spec sign(binary()) :: binary()
  def sign(message) when is_binary(message) do
    sign(message, sign_privkey())
  end

  @spec sign(binary(), sign_priv_key()) :: binary()
  def sign(message, privkey)
      when is_binary(message) and is_binary(privkey) do
    :enacl.sign_detached(message, privkey)
  end

  @doc """
  Checks if the message is signed with the given public key
  """
  @spec verify(binary(), binary()) :: true | false
  def verify(message, sign) do
    verify(message, sign, Keys.sign_pubkey())
  end

  @spec verify(binary(), binary(), pubkey()) :: true | false
  def verify(message, sign, pubkey)
      when is_binary(message) and is_binary(sign) and is_binary(pubkey) do
    case :enacl.sign_verify_detached(sign, message, pubkey) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @spec key_size_valid?(binary()) :: true | false
  def key_size_valid?(pubkey) when byte_size(pubkey) == @pub_size, do: true
  def key_size_valid?(_), do: false

  def handle_call(:sign_pubkey, _from, %{sign_pubkey: pubkey} = state) do
    {:reply, pubkey, state}
  end

  def handle_call(:sign_privkey, _from, %{sign_priv_file: file} = state) do
    privkey =
      case File.read(file) do
        {:ok, encr_priv} ->
          {:ok, key} = decrypt_key(encr_priv, pwd(:sign), @priv_sign_size)
          key

        _ ->
          {:error, :enoent}
      end

    {:reply, privkey, state}
  end

  def handle_call(:peer_keypair, _from, %{peer_pubkey: pub, peer_privkey: priv} = state) do
    {:reply, {pub, priv}, state}
  end

  ## Internal functions

  defp setup_sign_keys(pwd, keys_dir) do
    {pub_file, priv_file} = gen_sign_filename(keys_dir)

    case read_keys(pwd, pub_file, priv_file, @pub_size, @priv_sign_size) do
      {:error, :enoent} ->
        gen_new_sign(pwd, pub_file, priv_file)

      {pubkey, privkey} ->
        ## Check validity
        if check_sign_keys(pubkey, privkey) do
          {:ok, pubkey, priv_file}
        else
          ## Do something
        end
    end
  end

  defp setup_peer_keys(pwd, keys_dir) do
    {pub_file, priv_file} = gen_peer_filename(keys_dir)

    case read_keys(pwd, pub_file, priv_file, @pub_size, @priv_peer_size) do
      {:error, :enoent} ->
        gen_new_peer(pwd, pub_file, priv_file)

      {pubkey, privkey} ->
        ## Check validity
        if check_peer_keys(pubkey, privkey) do
          {:ok, pubkey, privkey}
        else
          ## Do something
        end
    end
  end

  defp gen_new_sign(pwd, pub_file, priv_file) do
    %{public: pubkey, secret: privkey} = :enacl.sign_keypair()

    if check_sign_keys(pubkey, privkey) do
      :ok = save_keys(pwd, pub_file, pubkey, priv_file, privkey)
      {:ok, pubkey, priv_file}
    else
      ## Why do we check the lib here?
      gen_new_sign(pwd, pub_file, priv_file)
    end
  end

  defp gen_new_peer(pwd, pub_file, priv_file) do
    %{public: sign_pubkey, secret: sign_privkey} = :enacl.sign_keypair()
    pubkey = :enacl.crypto_sign_ed25519_public_to_curve25519(sign_pubkey)
    privkey = :enacl.crypto_sign_ed25519_secret_to_curve25519(sign_privkey)

    if check_peer_keys(pubkey, privkey) do
      :ok = save_keys(pwd, pub_file, pubkey, priv_file, privkey)
      {:ok, pubkey, privkey}
    else
      ## Why do we check the lib here?
      gen_new_peer(pwd, pub_file, priv_file)
    end
  end

  defp gen_sign_filename(keys_dir) do
    gen_filename(keys_dir, @filename_sign_pub, @filename_sign_priv)
  end

  defp gen_peer_filename(keys_dir) do
    gen_filename(keys_dir, @filename_peer_pub, @filename_peer_priv)
  end

  defp gen_filename(keys_dir, pub_file, priv_file) do
    :ok = gen_dir(File.dir?(keys_dir), keys_dir)
    pub_file = Path.join(keys_dir, pub_file)
    priv_file = Path.join(keys_dir, priv_file)
    {pub_file, priv_file}
  end

  defp gen_dir(false, keys_dir), do: File.mkdir!(keys_dir)
  defp gen_dir(true, _), do: :ok

  ## Reads the keys from their respectve directory and returns
  ## their decrypted result. If the either of the file is not readable
  ## return an error
  defp read_keys(pwd, pub_file, priv_file, pub_size, priv_size) do
    case {File.read(pub_file), File.read(priv_file)} do
      {{:ok, encr_pub}, {:ok, encr_priv}} ->
        {:ok, pubkey} = decrypt_key(encr_pub, pwd, pub_size)
        {:ok, privkey} = decrypt_key(encr_priv, pwd, priv_size)
        {pubkey, privkey}

      _ ->
        {:error, :enoent}
    end
  end

  defp save_keys(pwd, pub_file, pubkey, priv_file, privkey) do
    encrypted_pub = encrypt_key(pubkey, pwd)
    encrypted_priv = encrypt_key(privkey, pwd)

    File.write!(pub_file, encrypted_pub)
    File.write!(priv_file, encrypted_priv)
  end

  defp encrypt_key(key, pwd) do
    ## Put leading 0s to ensure on decryption we are using the correct password
    ## Fix magic 0s
    :crypto.block_encrypt(:aes_ecb, hash(pwd), <<0::128, key::binary()>>)
  end

  defp decrypt_key(encrypted, pwd, size) do
    <<0::128, key::binary-size(size)>> = :crypto.block_decrypt(:aes_ecb, hash(pwd), encrypted)
    {:ok, key}
  end

  defp hash(binary), do: :crypto.hash(:sha256, binary)

  ## Checks weather the keypairs are working accordingly
  defp check_sign_keys(pubkey, privkey) do
    sample_msg = <<"sample message">>
    signature = :enacl.sign_detached(sample_msg, privkey)
    {:ok, sample_msg} == :enacl.sign_verify_detached(signature, sample_msg, pubkey)
  end

  defp check_peer_keys(pubkey, privkey) do
    pubkey == :enacl.curve25519_scalarmult_base(privkey)
  end

  ## Change get_env with fetch_env! ??

  defp pwd(:sign) do
    Application.get_env(:aecore, :sign_keys)[:pass]
  end

  defp pwd(:peer) do
    Application.get_env(:aecore, :peer_keys)[:pass]
  end

  defp dir(:sign) do
    Application.get_env(:aecore, :sign_keys)[:path]
  end

  defp dir(:peer) do
    Application.get_env(:aecore, :peer_keys)[:path]
  end
end
