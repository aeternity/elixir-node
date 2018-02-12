defmodule Aecore.Keys.Worker do
  @moduledoc """
  Key manager for AE node
  """
  use GenServer

  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx

  @filename_pub "key.pub"
  @filename_priv "key"
  @pub_key_length 65

  def start_link(_args) do
    GenServer.start_link(
      __MODULE__,
      %{
        pub: nil,
        priv: nil,
        pass: nil,
        keys_dir: nil,
        pub_file: nil,
        priv_file: nil,
        type: nil,
        algo: nil,
        digest: nil,
        curve: nil
      },
      name: __MODULE__
    )
  end

  @doc """
  Takes the public key of the receiver and
  the value that will be sended. Returns signed tx

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - value: The amount of a transaction

  """
  @spec sign_tx(binary(), integer(), integer(), integer(), integer()) :: {:ok, SignedTx.t()}
  def sign_tx(to_acc, value, nonce, fee, lock_time_block \\ 0) do
    {:ok, from_acc} = pubkey()
    {:ok, tx_data} = SpendTx.create(from_acc, to_acc, value, nonce, fee, lock_time_block)
    {:ok, signature} = sign(tx_data)
    signed_tx = %SignedTx{data: tx_data, signature: signature}
    {:ok, signed_tx}
  end

  @spec sign(term()) :: {:ok, binary()}
  def sign(msg) do
    GenServer.call(__MODULE__, {:sign, msg})
  end

  @spec sign(term(), binary()) :: {:ok, binary()}
  def sign(msg, priv_key) do
    GenServer.call(__MODULE__, {:sign, msg, priv_key})
  end

  @spec verify_tx(SignedTx.t()) :: boolean()
  def verify_tx(tx) do
    verify(tx.data, tx.signature, tx.data.from_acc)
  end

  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(msg, signature, pubkey) do
    GenServer.call(__MODULE__, {:verify, {msg, signature, pubkey}})
  end

  @spec pubkey() :: {:ok, binary()} | {:error, :key_not_found}
  def pubkey do
    GenServer.call(__MODULE__, :pubkey)
  end

  @spec open(binary()) :: {:ok, binary()} | {:error, :keys_not_loaded}
  def open(password) do
    GenServer.call(__MODULE__, {:open, password})
  end

  @spec new(binary()) :: {binary(), binary()} | :error
  def new(password) do
    GenServer.call(__MODULE__, {:new, password})
  end

  @spec set(binary(), binary(), binary()) :: :ok | :error
  def set(password, priv, pub) do
    GenServer.call(__MODULE__, {:set, password, priv, pub})
  end

  @spec delete() :: :ok | :error
  def delete() do
    GenServer.call(__MODULE__, :delete)
  end

  def init(state) do
    algo = :ecdsa
    key_type = :ecdh
    digest = :sha256
    curve = :secp256k1

    ## INFO: set the password to re-use keys between restarts
    password = Application.get_env(:aecore, :keys)[:password]
    keys_dir = Application.get_env(:aecore, :keys)[:dir]

    case :filelib.is_dir(keys_dir) do
      false ->
        :ok = :file.make_dir(keys_dir)

      true ->
        :ok
    end

    {
      :ok,
      %{
        state
        | algo: algo,
          type: key_type,
          digest: digest,
          curve: curve,
          pass: password,
          keys_dir: keys_dir
      },
      0
    }
  end

  def handle_call(
        {:verify, {term, signature, pub_key}},
        _from,
        %{algo: algo, digest: digest, curve: curve} = state
      ) do
    case is_valid_pub_key(pub_key) do
      true ->
        result =
          :crypto.verify(algo, digest, :erlang.term_to_binary(term), signature, [
                pub_key,
                :crypto.ec_curve(curve)
              ])

        {:reply, result, state}
      false ->
        {:reply, {:error, "Key length is not valid!"}, state}
    end
  end

  def handle_call(
        {:sign, term},
        _from,
        %{priv: priv_key, algo: algo, digest: digest, curve: curve} = state
      ) do
    signature =
      :crypto.sign(algo, digest, :erlang.term_to_binary(term), [priv_key, :crypto.ec_curve(curve)])

    {:reply, {:ok, signature}, state}
  end

  def handle_call(
        {:sign, term, priv_key},
        _from,
        %{algo: algo, digest: digest, curve: curve} = state
      ) do
    signature =
      :crypto.sign(algo, digest, :erlang.term_to_binary(term), [priv_key, :crypto.ec_curve(curve)])

    {:reply, {:ok, signature}, state}
  end

  def handle_call(:pubkey, _from, %{pub: nil} = state) do
    {:reply, {:error, :key_not_found}, state}
  end

  def handle_call(:pubkey, _from, %{pub: pubkey} = state) do
    {:reply, {:ok, pubkey}, state}
  end

  def handle_call(:delete, _from, %{pub_file: pub_file, priv_file: priv_file} = state) do
    try do
      :ok = :file.delete(pub_file)
      :ok = :file.delete(priv_file)
      {:reply, :ok, %{state | pub_file: nil, priv_file: nil, pub: nil, priv: nil}}
    catch
      _ ->
        {:reply, :error, state}
    end
  end

  def handle_call(
        {:new, password},
        _from,
        %{type: key_type, keys_dir: keys_dir, curve: curve} = state
      ) do
    try do
      {new_pub_file, new_priv_file} = p_gen_filename(keys_dir)

      {new_pub_key, new_priv_key} =
        p_gen_new(password, key_type, curve, new_pub_file, new_priv_file)

      {
        :reply,
        :ok,
        %{
          state
          | pub: new_pub_key,
            priv: new_priv_key,
            pass: password,
            pub_file: new_pub_file,
            priv_file: new_priv_file
        }
      }
    catch
      _ ->
        {:reply, :error, state}
    end
  end

  def handle_call({:open, password}, _from, %{pub_file: pub_file, priv_file: priv_file} = state) do
    try do
      {:ok, pub} = from_local_dir(pub_file)
      {:ok, priv} = from_local_dir(priv_file)
      pub0 = decrypt_pubkey(password, pub)
      priv0 = decrypt_privkey(password, priv)
      {:reply, :ok, %{state | pub: pub0, priv: priv0, pass: password}}
    catch
      _ ->
        {:reply, {:error, :keys_not_loaded}, state}
    end
  end

  def handle_call(
        {:set, password, priv, pub},
        _from,
        %{pub_file: pub_file, priv_file: priv_file} = state
      ) do
    try do
      enc_pub = encrypt_pubkey(password, pub)
      enc_priv = encrypt_privkey(password, priv)
      :ok = to_local_dir(pub_file, enc_pub)
      :ok = to_local_dir(priv_file, enc_priv)

      {:reply, :ok, %{state | pub: pub, priv: priv}}
    catch
      _ ->
        {:reply, {:error, :keys_not_loaded}, state}
    end
  end

  def handle_info(
        :timeout,
        %{pub: nil, priv: nil, pass: password, type: key_type, curve: curve, keys_dir: keys_dir} =
          state
      ) do
    try do
      {pub_file, priv_file} = p_gen_filename(keys_dir)

      {pub1, priv1} =
        case from_local_dir(pub_file) do
          {:error, :enoent} ->
            p_gen_new(password, key_type, curve, pub_file, priv_file)

          {:ok, pub} ->
            {:ok, priv} = from_local_dir(priv_file)
            pub0 = decrypt_pubkey(password, pub)
            priv0 = decrypt_privkey(password, priv)
            {pub0, priv0}
        end

      {:noreply, %{state | pub: pub1, priv: priv1, priv_file: priv_file, pub_file: pub_file}}
    catch
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  ## Internal

  defp hash(bin) do
    :crypto.hash(:sha256, bin)
  end

  defp encrypt_privkey(password, bin) do
    :crypto.block_encrypt(:aes_ecb, hash(password), bin)
  end

  defp encrypt_pubkey(password, bin) do
    ## TODO: is it safe to use 0s as padding? Consider moving to stream encryption API
    :crypto.block_encrypt(:aes_ecb, hash(password), padding128(bin))
  end

  defp decrypt_privkey(password, bin) do
    :crypto.block_decrypt(:aes_ecb, hash(password), bin)
  end

  defp decrypt_pubkey(password, bin) do
    <<pub::65-binary, _padding::binary>> = :crypto.block_decrypt(:aes_ecb, hash(password), bin)
    pub
  end

  defp is_valid_pub_key(pub_key_str) do
    pub_key_str
    |> byte_size() == @pub_key_length
  end

  defp padding128(bin) do
    pad0 = 128 - :erlang.size(bin)
    pad1 = pad0 * 8
    <<bin::binary, 0::size(pad1)>>
  end

  defp p_gen_filename(keys_dir) do
    ## TODO: consider checking whats in the dir and genrerating file with suffix
    pub_file = :filename.join(keys_dir, @filename_pub)
    priv_file = :filename.join(keys_dir, @filename_priv)
    {pub_file, priv_file}
  end

  defp p_gen_new(nil, _, _, _, _) do
    :no_password_provided
  end

  defp p_gen_new(password, key_type, curve, pub_filename, priv_filename) do
    {new_pub_key, new_priv_key} = :crypto.generate_key(key_type, :crypto.ec_curve(curve))
    enc_pub = encrypt_pubkey(password, new_pub_key)
    enc_priv = encrypt_privkey(password, new_priv_key)
    :ok = to_local_dir(pub_filename, enc_pub)
    :ok = to_local_dir(priv_filename, enc_priv)
    {new_pub_key, new_priv_key}
  end

  defp to_local_dir(new_file, bin) do
    case :file.read_file(new_file) do
      {:error, :enoent} ->
        {:ok, io_device} = :file.open(new_file, [:write, :binary, :raw])
        :ok = :file.write_file(new_file, bin)
        :ok = :file.close(io_device)

      {:ok, _out} ->
        ## info: for now do not let to overwrite existing keys
        {:error, :existing_keys}
    end
  end

  defp from_local_dir(new_file) do
    :file.read_file(new_file)
  end
end
