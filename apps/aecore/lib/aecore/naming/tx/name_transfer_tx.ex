defmodule Aecore.Naming.Tx.NameTransferTx do
  @moduledoc """
  Aecore structure of naming transfer.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.Naming
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet

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
  @spec is_valid?(NameTransferTx.t()) :: boolean()
  def is_valid?(%NameTransferTx{
        hash: _hash,
        target: _target
      }) do
    # TODO validate hash byte size
    # TODO validate target pubkey byte size
    true
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the naming state for claim transfers.
  """
  @spec process_chainstate!(
          NameTransferTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %NameTransferTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming_state
      ) do
    sender_account_state = Map.get(accounts, sender, Account.empty())

    case preprocess_check(
           tx,
           sender_account_state,
           sender,
           fee,
           nonce,
           block_height,
           naming_state
         ) do
      :ok ->
        new_senderount_state =
          sender_account_state
          |> deduct_fee(fee)
          |> Account.transaction_out_nonce_update(nonce)

        updated_accounts_chainstate = Map.put(accounts, sender, new_senderount_state)

        claim_to_update = Map.get(naming_state, tx.hash)
        claim = %{claim_to_update | owner: tx.target}
        updated_naming_chainstate = Map.put(naming_state, tx.hash, claim)

        {updated_accounts_chainstate, updated_naming_chainstate}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the NameTransferTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          NameTransferTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check(tx, account_state, sender, fee, nonce, _block_height, naming_state) do
    claim = Map.get(naming_state, tx.hash)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      claim == nil ->
        {:error, "Name has not been claimed"}

      claim.owner != sender ->
        {:error, "Sender is not claim owner"}

      claim.status == :revoked ->
        {:error, "Claim is revoked"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), tx_type_state()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end
end
