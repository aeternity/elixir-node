defmodule Aecore.Naming.Tx.NameTransferTx do
  @moduledoc """
  Aecore structure of naming transfer.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.Naming
  alias Aeutil.Hash
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.AccountStateTree

  require Logger

  @typedoc "Expected structure for the Transfer Transaction"
  @type payload :: %{
          hash: binary(),
          target: Wallet.pubkey()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameTransferTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the NameTransferTx Transaction type"
  @type t :: %NameTransferTx{
          hash: binary(),
          target: Wallet.pubkey()
        }

  @doc """
  Definition of Aecore NameTransferTx structure

  ## Parameters
  - hash: hash of name to be transfered
  - target: target public key to transfer to
  """
  defstruct [:hash, :target]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameTransferTx.t()
  def init(%{hash: hash, target: target}) do
    %NameTransferTx{hash: hash, target: target}
  end

  @doc """
  Checks target and hash byte sizes
  """
  @spec validate(NameTransferTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameTransferTx{hash: hash, target: target}) do
    with true <- byte_size(hash) == Hash.get_hash_bytes_size(),
         :ok <- Wallet.key_size_valid?(target) do
      :ok
    else
      false ->
        {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash))}"}

      err ->
        err
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Changes the naming state for claim transfers.
  """
  @spec process_chainstate(
          NameTransferTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.accounts_state(),
          tx_type_state()
        ) :: {AccountStateTree.accounts_state(), tx_type_state()}
  def process_chainstate(
        %NameTransferTx{} = tx,
        sender,
        fee,
        nonce,
        _block_height,
        accounts,
        naming_state
      ) do
    new_senderount_state =
      accounts
      |> Account.get_account_state(sender)
      |> deduct_fee(fee)
      |> Account.transaction_out_nonce_update(nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_senderount_state)

    claim_to_update = Map.get(naming_state, tx.hash)
    claim = %{claim_to_update | owner: tx.target}
    updated_naming_chainstate = Map.put(naming_state, tx.hash, claim)

    {updated_accounts_chainstate, updated_naming_chainstate}
  end

  @doc """
  Checks whether all the data is valid according to the NameTransferTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          NameTransferTx.t(),
          Wallet.pubkey(),
          AccountStateTree.accounts_state(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _nonce, _block_height, naming_state) do
    claim = Map.get(naming_state, tx.hash)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}

      claim == nil ->
        {:error, "#{__MODULE__}: Name has not been claimed: #{inspect(claim)}"}

      claim.owner != sender ->
        {:error,
         "#{__MODULE__}: Sender is not claim owner: #{inspect(claim.owner)}, #{inspect(sender)}"}

      claim.status == :revoked ->
        {:error, "#{__MODULE__}: Claim is revoked: #{inspect(claim.status)}"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), tx_type_state()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end
end
