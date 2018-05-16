defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Account.Tx.CoinbaseTx
  alias Aewallet.Signing
  alias Aeutil.Serialization
  alias Aeutil.Bits
  alias Aeutil.Hash

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Wallet.pubkey())
        }

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %SpendTx{} structure
     - signature: Signed %SpendTx{} with the private key of the sender
  """

  defstruct [:data, :signatures]
  use ExConstructor

  @spec create(DataTx.t(), list(Signature.t())) :: SignedTx.t()
  def create(data, signatures \\ []) do
    %SignedTx{data: data, signatures: signatures}
  end

  def data_tx(%SignedTx{data: data}) do
    data
  end

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%SignedTx{data: data}) do
    data.type == CoinbaseTx
  end

  @spec validate(SignedTx.t()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx) do
    if signatures_valid?(tx) do
      DataTx.validate(data)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec process_chainstate(ChainState.chainstate(), non_neg_integer(), SignedTx.t()) ::
          ChainState.chainstate()
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

  @spec sign_tx(DataTx.t() | SignedTx.t(), binary(), binary()) ::
          {:ok, SignedTx.t()} | {:error, binary()}
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
      |> Signing.sign(priv_key)

    {success, new_sigs} =
      sigs
      |> Enum.zip(DataTx.senders(data))
      |> Enum.reduce({false, []}, fn {sig, sender}, {success, acc} ->
        if sender == pub_key do
          {true, [new_signature | acc]}
        else
          {success, [sig | acc]}
        end
      end)

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

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
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

  @spec serialize(SignedTx.t()) :: map()
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
        %{
          "data" => DataTx.serialize(tx.data),
          "signature" => Serialization.serialize_value(:signature)
        }
    end
  end

  @spec deserialize(map()) :: DataTx.t()
  def deserialize(tx) do
    signed_tx = Serialization.deserialize_value(tx)
    data = DataTx.deserialize(signed_tx.data)

    cond do
      signed_tx.signature != nil ->
        create(data, [signed_tx.signature])

      signed_tx.signatures != nil ->
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
            Logger.error("Missing signature of #{acc}")
            false

          !Wallet.key_size_valid?(acc) ->
            Logger.error("Wrong sender size")
            false

          Signing.verify(data_binary, sig, acc) ->
            validity

          true ->
            Logger.error("Signature of #{acc} invalid")
            false
        end
      end)
    end
  end

  @spec rlp_encode(SignedTx.t()) :: binary() | atom()
  def rlp_encode(%SignedTx{} = tx) do
    [
      type_to_tag(SignedTx),
      get_version(SignedTx),
      tx.signatures,
      DataTx.rlp_encode(tx.data)
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(tx) do
    {:error, "Invalid SignedTx data #{inspect(tx)}"}
  end

  @spec rlp_decode(binary()) :: SignedTx.t() | atom()
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    _ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      SignedTx ->
        [signatures, tx_data] = rest_data

        %SignedTx{data: DataTx.rlp_decode(tx_data), signatures: signatures}

      _ ->
        {:error, "Illegal SignedTx serialization"}
    end
  end

  def rlp_decode(_) do
    {:error, "Invalid SignedTx serialization"}
  end

  @spec type_to_tag(atom()) :: integer() | atom()
  defp type_to_tag(SignedTx), do: 11
  defp type_to_tag(_), do: :unknown_type

  @spec tag_to_type(integer()) :: SignedTx | atom()
  defp tag_to_type(11), do: SignedTx
  defp tag_to_type(_), do: :unknown_tag

  @spec get_version(SignedTx) :: integer() | atom()
  defp get_version(SignedTx), do: 1
  defp get_version(_), do: :unknown_struct_version
end
