defmodule Aecore.Keys do
  @moduledoc """
  Module for handling the Wallet (signing) keys and Peer keys.
  Keys are created on the first run of the project and saved in their respective directories.
  """

  alias Aeutil.Bits
  alias Aecore.Chain.Identifier

  @typedoc "Defines what type of keypair we could have"
  @type keypair_type :: :sign | :peer

  @typedoc "Public key for signing or for peers - 32 bytes in size"
  @type pubkey :: binary()

  @typedoc "Private key for signing - 64 bytes in size"
  @type sign_priv_key :: binary()

  @typedoc "Private key for peers - 32 bytes in size"
  @type peer_priv_key :: binary()

  @type sign_keypair :: {pubkey(), sign_priv_key()}
  @type peer_keypair :: {pubkey(), peer_priv_key()}
  @type message :: binary()
  @type signature :: binary()

  @pub_size 32

  @peer_key_encode "pp"
  @peer_key_decode "pp$"

  @filename_sign_pub "sign_key.pub"
  @filename_sign_priv "sign_key"

  @filename_peer_pub "peer_key.pub"
  @filename_peer_priv "peer_key"

  def pubkey_size, do: @pub_size

  @doc """
  Signs the given message and returns the signature
  """
  @spec sign(message()) :: signature()
  def sign(message) when is_binary(message) do
    {_, privkey} = keypair(:sign)
    sign(message, privkey)
  end

  @spec sign(message(), sign_priv_key()) :: signature()
  def sign(message, privkey) when is_binary(message) and is_binary(privkey) do
    :enacl.sign_detached(message, privkey)
  end

  @doc """
  Checks if the message is signed with the miners key
  """
  @spec verify(message(), signature()) :: boolean()
  def verify(message, sign) do
    {pubkey, _} = keypair(:sign)
    verify(message, sign, pubkey)
  end

  @doc """
  Checks if the message is signed with the given public key
  """
  @spec verify(message(), signature(), pubkey()) :: boolean()
  def verify(message, sign, pubkey)
      when is_binary(message) and is_binary(sign) and is_binary(pubkey) do
    case :enacl.sign_verify_detached(sign, message, pubkey) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @spec key_size_valid?(binary()) :: boolean()
  def key_size_valid?(%Identifier{value: pubkey})
      when byte_size(pubkey) == @pub_size,
      do: true

  def key_size_valid?(pubkey)
      when byte_size(pubkey) == @pub_size,
      do: true

  def key_size_valid?(_), do: false

  @doc """
  Returns a tuple with the specified keypair. If only the type of keypair is given
  the function will return the miners :sign and :peer keypair. If a suffix is added,
  additional keypairs are going to be returned.

  The accepter keypair types are:
    * `:sign` - returns a tuple with signing keys {pub, priv}
    * `:peer` - returns a tuple with peers keys {pub, priv}

  # Examples
      iex> keypair(:sign)
      iex> {pubkey(), sign_priv_key()}

      iex> keypair(:peer)
      iex> {pubkey(), peer_priv_key()}

      iex> keypair(:sign, "1")
      iex> {pubkey(), sign_priv_key()}
  """
  @spec keypair(keypair_type(), String.t()) :: sign_keypair() | peer_keypair()
  def keypair(type, suffix \\ "") do
    {pub_file, priv_file} = gen_filename(suffix, type)

    case read_keypair(pwd(type), pub_file, priv_file) do
      {:error, :enoent} ->
        new_keypair(pub_file, priv_file, type)

      {pubkey, privkey} ->
        if check_keypair(pubkey, privkey, type) do
          {pubkey, privkey}
        else
          throw({:error, :invalid_sign_keypair})
        end
    end
  end

  defp new_keypair(pub_file, priv_file, :sign) do
    %{public: pubkey, secret: privkey} = :enacl.sign_keypair()
    :ok = save_keypair(pwd(:sign), pub_file, pubkey, priv_file, privkey)
    {pubkey, privkey}
  end

  defp new_keypair(pub_file, priv_file, :peer) do
    %{public: sign_pubkey, secret: sign_privkey} = :enacl.sign_keypair()

    pubkey = :enacl.crypto_sign_ed25519_public_to_curve25519(sign_pubkey)
    privkey = :enacl.crypto_sign_ed25519_secret_to_curve25519(sign_privkey)

    :ok = save_keypair(pwd(:peer), pub_file, pubkey, priv_file, privkey)
    {pubkey, privkey}
  end

  defp gen_filename(suffix, :sign) do
    gen_filename(dir(:sign), @filename_sign_pub, @filename_sign_priv, suffix)
  end

  defp gen_filename(suffix, :peer) do
    gen_filename(dir(:peer), @filename_peer_pub, @filename_peer_priv, suffix)
  end

  defp gen_filename(keys_dir, pub_file, priv_file, suffix) do
    :ok = gen_dir(File.dir?(keys_dir), keys_dir)
    pub_file = Path.join(keys_dir, "#{suffix}_" <> pub_file)
    priv_file = Path.join(keys_dir, "#{suffix}_" <> priv_file)
    {pub_file, priv_file}
  end

  defp gen_dir(false, keys_dir), do: File.mkdir!(keys_dir)
  defp gen_dir(true, _), do: :ok

  # Reads the keys from their respectve directory and returns
  # their decrypted result. If either of the files is not readable - return an error
  defp read_keypair(pwd, pub_file, priv_file) do
    case {File.read(pub_file), File.read(priv_file)} do
      {{:ok, encr_pub}, {:ok, encr_priv}} ->
        pubkey = decrypt_key(encr_pub, pwd)
        privkey = decrypt_key(encr_priv, pwd)
        {pubkey, privkey}

      _ ->
        {:error, :enoent}
    end
  end

  defp save_keypair(pwd, pub_file, pubkey, priv_file, privkey) do
    File.write!(pub_file, encrypt_key(pubkey, pwd))
    File.write!(priv_file, encrypt_key(privkey, pwd))
  end

  defp encrypt_key(key, pwd), do: :crypto.block_encrypt(:aes_ecb, hash(pwd), key)

  defp decrypt_key(encrypted, pwd), do: :crypto.block_decrypt(:aes_ecb, hash(pwd), encrypted)

  defp hash(binary), do: :crypto.hash(:sha256, binary)

  # Checks whether the keypairs are working accordingly
  defp check_keypair(pubkey, privkey, :sign) do
    sample_msg = <<"sample message">>
    signature = :enacl.sign_detached(sample_msg, privkey)
    {:ok, sample_msg} == :enacl.sign_verify_detached(signature, sample_msg, pubkey)
  end

  defp check_keypair(pubkey, privkey, :peer) do
    pubkey == :enacl.curve25519_scalarmult_base(privkey)
  end

  @doc """
  Returns encoded version of a Peer key, public or private
  """
  @spec peer_encode(pubkey() | peer_priv_key()) :: binary()
  def peer_encode(key) do
    Bits.encode58c(@peer_key_encode, key)
  end

  @doc """
  Returns a decoded version of a Peer key, public or private
  """
  @spec peer_decode(binary()) :: pubkey() | peer_priv_key()
  def peer_decode(<<@peer_key_decode, payload::binary>>) do
    Bits.decode58(payload)
  end

  defp pwd(:sign) do
    {:ok, opts} = sign_keys_opts()
    opts[:pass]
  end

  defp pwd(:peer) do
    {:ok, opts} = peer_keys_opts()
    opts[:pass]
  end

  defp dir(:sign) do
    {:ok, opts} = sign_keys_opts()
    Application.app_dir(:aecore, "priv") <> opts[:path]
  end

  defp dir(:peer) do
    {:ok, opts} = peer_keys_opts()
    Application.app_dir(:aecore, "priv") <> opts[:path]
  end

  defp sign_keys_opts, do: Application.fetch_env(:aecore, :sign_keys)
  defp peer_keys_opts, do: Application.fetch_env(:aecore, :peer_keys)
end
