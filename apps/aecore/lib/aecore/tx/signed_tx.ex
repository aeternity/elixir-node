defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Module defining the Signed transaction
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aeutil.Bits
  alias Aeutil.Hash

  require Logger

  @typedoc "Structure of the SignedTx Transaction type"
  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Keys.pubkey())
        }

  @version 1

  defstruct [:data, :signatures]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(DataTx.t(), list(Keys.pubkey())) :: SignedTx.t()
  def create(data, signatures \\ []) do
    %SignedTx{data: data, signatures: signatures}
  end

  @spec validate(SignedTx.t()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: %DataTx{senders: data_senders} = data} = tx) do
    pubkeys = for %Identifier{value: pubkey} <- data_senders, do: pubkey

    if DataTx.chainstate_senders?(data) || signatures_valid?(tx, pubkeys) do
      DataTx.validate(data)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec check_apply_transaction(Chainstate.t(), non_neg_integer(), SignedTx.t()) ::
          {:ok, Chainstate.t()} | {:error, String.t()}
  def check_apply_transaction(chainstate, block_height, %SignedTx{data: data} = tx) do
    with true <- signatures_valid?(tx, DataTx.senders(data, chainstate)),
         :ok <- DataTx.preprocess_check(chainstate, block_height, data) do
      DataTx.process_chainstate(chainstate, block_height, data)
    else
      false ->
        {:error, "#{__MODULE__}: Signatures invalid"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  # Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with
  """
  @spec sign_tx(DataTx.t() | SignedTx.t(), binary()) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def sign_tx(%DataTx{} = tx, priv_key) do
    sign_tx(%SignedTx{data: tx, signatures: []}, priv_key)
  end

  def sign_tx(%SignedTx{data: data, signatures: sigs}, priv_key) do
    new_signature =
      data
      |> DataTx.rlp_encode()
      |> Keys.sign(priv_key)

    # We need to make sure the sigs are sorted in order for the json/websocket api to function properly
    {:ok, %SignedTx{data: data, signatures: Enum.sort([new_signature | sigs])}}
  end

  def sign_tx(tx, _priv_key) do
    {:error, "#{__MODULE__}: Wrong Transaction data structure: #{inspect(tx)}"}
  end

  def get_sign_max_size do
    Application.get_env(:aecore, :signed_tx)[:sign_max_size]
  end

  @spec hash_tx(SignedTx.t() | DataTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    hash_tx(data)
  end

  def hash_tx(%DataTx{} = data) do
    Hash.hash(DataTx.rlp_encode(data))
  end

  @spec reward(DataTx.t(), Account.t()) :: Account.t()
  def reward(%DataTx{type: type, payload: payload}, account_state) do
    type.reward(payload, account_state)
  end

  @spec base58c_encode(binary) :: String.t()
  def base58c_encode(bin) do
    Bits.encode58c("tx", bin)
  end

  @spec base58c_decode(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode(<<"tx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  @spec base58c_encode_root(binary) :: String.t()
  def base58c_encode_root(bin) do
    Bits.encode58c("bx", bin)
  end

  @spec base58c_decode_root(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode_root(<<"bx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_root(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  @spec base58c_encode_signature(binary) :: nil | String.t()
  def base58c_encode_signature(bin) do
    if bin == nil do
      nil
    else
      Bits.encode58c("sg", bin)
    end
  end

  @spec base58c_decode_signature(String.t()) :: binary() | {:error, String.t()}
  def base58c_decode_signature(<<"sg$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_signature(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec serialize(map()) :: map()
  def serialize(%SignedTx{} = tx) do
    signatures_length = length(tx.signatures)

    case signatures_length do
      0 ->
        %{"data" => DataTx.serialize(tx.data)}

      1 ->
        signature_serialized =
          tx.signatures
          |> Enum.at(0)
          |> Serialization.serialize_value(:signature)

        %{"data" => DataTx.serialize(tx.data), "signature" => signature_serialized}

      _ ->
        serialized_signatures =
          for signature <- tx.signatures do
            Serialization.serialize_value(signature, :signature)
          end

        %{
          "data" => DataTx.serialize(tx.data),
          "signatures" => serialized_signatures
        }
    end
  end

  @spec deserialize(map()) :: SignedTx.t()
  def deserialize(tx) do
    signed_tx = Serialization.deserialize_value(tx)
    data = DataTx.deserialize(signed_tx.data)

    cond do
      Map.has_key?(signed_tx, :signature) && signed_tx.signature != nil ->
        create(data, [signed_tx.signature])

      Map.has_key?(signed_tx, :signatures) && signed_tx.signatures != nil ->
        create(data, signed_tx.signatures)

      true ->
        create(data, [])
    end
  end

  @doc """
  Checks if SignedTx contains a valid signature for each sender
  """
  @spec signatures_valid?(SignedTx.t(), list(Keys.pubkey())) :: boolean()
  def signatures_valid?(%SignedTx{data: data, signatures: sigs}, senders) do
    if length(sigs) != length(senders) do
      Logger.error("Wrong signature count")
      false
    else
      data_binary = DataTx.rlp_encode(data)
      check_multiple_signatures(sigs, data_binary, senders)
    end
  end

  @doc """
  Checks if the SignedTx contains a valid signature for the provided public key
  """
  @spec signature_valid_for?(SignedTx.t(), Keys.pubkey()) :: boolean()
  def signature_valid_for?(%SignedTx{data: data, signatures: signatures}, pubkey) do
    data_binary = DataTx.rlp_encode(data)

    case single_signature_check(signatures, data_binary, pubkey) do
      {:ok, _} ->
        true

      :error ->
        false
    end
  end

  @spec check_multiple_signatures(list(binary()), binary(), list(Keys.pubkey())) :: boolean()
  defp check_multiple_signatures(signatures, data_binary, [pubkey | remaining_pubkeys]) do
    case single_signature_check(signatures, data_binary, pubkey) do
      {:ok, remaining_signatures} ->
        check_multiple_signatures(remaining_signatures, data_binary, remaining_pubkeys)

      :error ->
        false
    end
  end

  defp check_multiple_signatures([], _data_binary, []) do
    true
  end

  defp check_multiple_signatures(_, _, _) do
    false
  end

  @spec single_signature_check(list(binary()), binary(), Keys.pubkey()) ::
          {:ok, list(binary())} | :error
  defp single_signature_check(signatures, data_binary, pubkey) do
    if Keys.key_size_valid?(pubkey) do
      do_single_signature_check(signatures, data_binary, pubkey)
    else
      Logger.error("Wrong pubkey size #{inspect(pubkey)}")
      :error
    end
  end

  @spec do_single_signature_check(list(binary()), binary(), Keys.pubkey()) ::
          {:ok, list(binary())} | :error
  defp do_single_signature_check([signature | rest_signatures], data_binary, pubkey) do
    if Keys.verify(data_binary, signature, pubkey) do
      {:ok, rest_signatures}
    else
      case do_single_signature_check(rest_signatures, data_binary, pubkey) do
        {:ok, unchecked_sigs} ->
          {:ok, [signature | unchecked_sigs]}

        :error ->
          :error
      end
    end
  end

  defp do_single_signature_check([], _data_binary, pubkey) do
    Logger.error("Signature of #{inspect(pubkey)} invalid")
    :error
  end

  @spec encode_to_list(SignedTx.t()) :: list()
  def encode_to_list(%SignedTx{data: %DataTx{} = data} = tx) do
    [
      :binary.encode_unsigned(@version),
      Enum.sort(tx.signatures),
      DataTx.rlp_encode(data)
    ]
  end

  # Consider making a ListUtils module
  @spec is_sorted?(list(binary)) :: boolean()
  defp is_sorted?([]), do: true
  defp is_sorted?([sig]) when is_binary(sig), do: true

  defp is_sorted?([sig1, sig2 | rest]) when is_binary(sig1) and is_binary(sig2) do
    sig1 < sig2 and is_sorted?([sig2 | rest])
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def decode_from_list(@version, [signatures, data]) do
    with {:ok, data} <- DataTx.rlp_decode(data),
         true <- is_sorted?(signatures) do
      {:ok, %SignedTx{data: data, signatures: signatures}}
    else
      {:error, _} = error ->
        error

      false ->
        {:error, "#{__MODULE__}: Signatures are not sorted"}
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
