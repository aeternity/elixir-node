defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aewallet.Signing
  alias Aeutil.Serialization
  alias Aeutil.Bits
  alias Aeutil.Hash

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signature: binary()
        }

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %SpendTx{} structure
     - signature: Signed %SpendTx{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%{data: %{sender: key}, signature: signature}) do
    key == nil && signature == nil
  end

  @doc """
  Checks weather the signature is correct.
  """
  @spec validate(SignedTx.t()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx) do
    if Signing.verify(DataTx.rlp_encode(data), tx.signature, data.sender) do
      :ok
    else
      {:error, "#{__MODULE__}: Can't verify the signature
      with the following public key: #{inspect(data.sender)}"}
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
  @spec sign_tx(DataTx.t(), binary()) :: {:ok, SignedTx.t()}
  def sign_tx(%DataTx{} = tx, priv_key) when byte_size(priv_key) == 32 do
    signature = Signing.sign(DataTx.rlp_encode(tx), priv_key)

    if byte_size(signature) <= get_sign_max_size() do
      {:ok, %SignedTx{data: tx, signature: signature}}
    else
      {:error, "Wrong signature size"}
    end
  end

  def sign_tx(%DataTx{} = _tx, priv_key) do
    {:error, "#{__MODULE__}: Wrong key size: #{inspect(priv_key)}"}
  end

  def sign_tx(tx, _priv_key) do
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
    {:error, "Wrong data"}
  end

  @spec rlp_encode(DataTx.t(SignedTx.t())) :: binary() | atom()
  def rlp_encode(%SignedTx{} = tx) do
    signatures =
      for sig <- [tx.signature] do
        # workaround - should be removed when CoinbaseTx will have its own structure
        if sig == nil do
          ExRLP.encode(<<0>>)
        else
          ExRLP.encode(sig)
        end
      end

    ExRLP.encode([
      type_to_tag(SignedTx),
      get_version(SignedTx),
      signatures,
      DataTx.rlp_encode(tx.data)
    ])
  end

  def rlp_encode(_) do
    :invalid_signedtx
  end

  @spec rlp_decode(binary()) :: SignedTx.t() | atom()
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      SignedTx ->
        [signatures, tx_data] = rest_data

        decoded_signatures =
          for sig <- signatures do
            ExRLP.decode(sig)
          end

        %SignedTx{data: DataTx.rlp_decode(tx_data), signature: decoded_signatures}

      _ ->
        :invalid_serialization
    end
  end

  def rlp_decode(_) do
    :invalid_serialization
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
