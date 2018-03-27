defmodule Aecore.Structures.SignedTx.Signature do
  @moduledoc """
  Aecore structure of a tx signature
  """

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.Account
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SignedTx.Signature
  alias Aecore.Chain.Chainstate
  alias Aewallet.Signing
  alias Aeutil.Serialization

  require Logger

  @type t :: %Signature{
          signature: binary(),
          nonce: integer()
        }

  @doc """
  Definition of Aecore Signature structure

  ## Parameters
  TODO
     - signature: Signed %SpendTx{} with the private key of the sender
  """
  defstruct [:signature, :nonce]
  use ExConstructor

  @spec process_chainstate!(Chainstate.chainstate(), Signature.t(), Wallet.pubkey(), DataTx.t()) ::
          Chainstate.chainstate()
  def process_chainstate!(chainstate, %Signature{nonce: nonce} = signature, acc, payload) do
    if !is_valid?(signature, acc, payload) do
      throw({:error, "Invalid signature for #{acc}"})
    end

    new_accounts =
      Map.update(chainstate.accounts, acc, Account.empty(), fn state ->
        Account.apply_nonce!(state, nonce)
      end)

    %{chainstate | accounts: new_accounts}
  end

  @spec is_valid?(Signature.t(), Wallet.pubkey(), DataTx.t()) :: boolean()
  def is_valid?(%Signature{nonce: nonce, signature: sig}, acc, tx) do
    tx
    |> DataTx.serialize()
    |> Map.put(:nonce, nonce)
    |> Serialization.pack_binary()
    |> Signing.verify(sig, acc)
  end

  @spec sign_tx(DataTx.t(), integer(), Wallet.pubkey()) ::
          {:ok, Signature.t()} | {:error, binary()}
  def sign_tx(%DataTx{} = tx, nonce, priv_key) do
    signature =
      tx
      |> DataTx.serialize()
      |> Map.put(:nonce, nonce)
      |> Serialization.pack_binary()
      |> Signing.sign(priv_key)

    {:ok, %Signature{nonce: nonce, signature: signature}}
  end

  def sign_tx(_tx, _priv_key) do
    {:error, "Wrong Transaction data structure"}
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end
end
