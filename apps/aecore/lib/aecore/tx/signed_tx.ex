defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aeutil.Serialization
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aeutil.Bits
  alias Aeutil.Hash

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Keys.pubkey())
        }

  @version 1

  defstruct [:data, :signatures]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(DataTx.t(), list(Keys.pubkey())) :: t()
  def create(data, signatures \\ []) do
    %SignedTx{data: data, signatures: signatures}
  end

  def data_tx(%SignedTx{data: data}) do
    data
  end

  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx) do
    if signatures_valid?(tx) do
      DataTx.validate(data)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec validate(t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx, block_height) do
    if signatures_valid?(tx) do
      DataTx.validate(data, block_height)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec process_chainstate(Chainstate.t(), non_neg_integer(), t()) ::
          {:ok, Chainstate.t()} | {:error, String.t()}
  def process_chainstate(chainstate, block_height, %SignedTx{data: data}) do
    with :ok <- DataTx.preprocess_check(chainstate, block_height, data) do
      DataTx.process_chainstate(chainstate, block_height, data)
    else
      err ->
        err
    end
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with

  """

  @spec sign_tx(DataTx.t() | t(), binary(), binary()) :: {:ok, t()} | {:error, String.t()}
  def sign_tx(%DataTx{} = tx, pub_key, priv_key) do
    signatures =
      for _ <- DataTx.senders(tx) do
        nil
      end

    sign_tx(%SignedTx{data: tx, signatures: signatures}, pub_key, priv_key)
  end

  def sign_tx(%SignedTx{data: data, signatures: sigs}, pub_key, priv_key) do
    new_signature =
      data
      |> DataTx.rlp_encode()
      |> Keys.sign(priv_key)

    {success, new_sigs_reversed} =
      sigs
      |> Enum.zip(DataTx.senders(data))
      |> Enum.reduce({false, []}, fn {sig, sender}, {success, acc} ->
        if sender == pub_key do
          {true, [new_signature | acc]}
        else
          {success, [sig | acc]}
        end
      end)

    new_sigs = Enum.reverse(new_sigs_reversed)

    if success do
      {:ok, %SignedTx{data: data, signatures: new_sigs}}
    else
      {:error, "#{__MODULE__}: Not in senders"}
    end
  end

  def sign_tx(tx, _pub_key, _priv_key) do
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

  def base58c_encode(bin) do
    Bits.encode58c("tx", bin)
  end

  def base58c_decode(<<"tx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  def base58c_encode_root(bin) do
    Bits.encode58c("bx", bin)
  end

  def base58c_decode_root(<<"bx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_root(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  def base58c_encode_signature(bin) do
    if bin == nil do
      nil
    else
      Bits.encode58c("sg", bin)
    end
  end

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

  @spec deserialize(map()) :: t()
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

  defp signatures_valid?(%SignedTx{data: data, signatures: sigs}) do
    if length(sigs) != length(DataTx.senders(data)) do
      Logger.error("Wrong signature count")
      false
    else
      data_binary = DataTx.rlp_encode(data)

      sigs
      |> Enum.zip(DataTx.senders(data))
      |> Enum.reduce(true, fn {sig, acc}, validity ->
        cond do
          sig == nil ->
            Logger.error("Missing signature of #{inspect(acc)}")
            false

          !Keys.key_size_valid?(acc) ->
            Logger.error("Wrong sender size #{inspect(acc)}")
            false

          Keys.verify(data_binary, sig, acc) ->
            validity

          true ->
            Logger.error("Signature of #{inspect(acc)} invalid")
            false
        end
      end)
    end
  end

  def encode_to_list(%SignedTx{} = tx) do
    [
      @version,
      tx.signatures,
      DataTx.rlp_encode(tx.data)
    ]
  end

  def decode_from_list(@version, [signatures, data]) do
    case DataTx.rlp_decode(data) do
      {:ok, data} ->
        {:ok, %SignedTx{data: data, signatures: signatures}}

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
