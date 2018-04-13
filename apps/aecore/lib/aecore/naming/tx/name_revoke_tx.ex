defmodule Aecore.Naming.Tx.NameRevokeTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.Naming
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

  require Logger

  @typedoc "Expected structure for the Revoke Transaction"
  @type payload :: %{
          hash: binary()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameRevokeTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the NameRevokeTx Transaction type"
  @type t :: %NameRevokeTx{
          hash: binary()
        }

  @doc """
  Definition of Aecore NameRevokeTx structure

  ## Parameters
  - hash: hash of name to be revoked
  """
  defstruct [:hash]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameRevokeTx.t()
  def init(%{
        hash: hash
      }) do
    %NameRevokeTx{hash: hash}
  end

  @doc """
  Checks name hash byte size
  """
  @spec is_valid?(NameRevokeTx.t()) :: boolean()
  def is_valid?(%NameRevokeTx{
        hash: _hash
      }) do
    # TODO validate hash byte size
    true
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          NameRevokeTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %NameRevokeTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming_state
      ) do
    sender_account_state = Account.get_account_state(accounts, sender)

    preprocess_check!(
      tx,
      sender_account_state,
      sender,
      fee,
      nonce,
      block_height,
      naming_state
    )

    new_senderount_state =
      sender_account_state
      |> deduct_fee(fee)
      |> Account.transaction_out_nonce_update(nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_senderount_state)

    claim_to_update = Map.get(naming_state, tx.hash)

    claim = %{
      claim_to_update
      | status: :revoked,
        expires: block_height + Naming.get_revoke_expiration_ttl()
    }

    updated_naming_chainstate = Map.put(naming_state, tx.hash, claim)

    {updated_accounts_chainstate, updated_naming_chainstate}
  end

  @doc """
  Checks whether all the data is valid according to the NameRevokeTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          NameRevokeTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check!(tx, account_state, sender, fee, nonce, _block_height, naming_state) do
    claim = Map.get(naming_state, tx.hash)

    cond do
      account_state.balance - fee < 0 ->
        throw({:error, "Negative balance"})

      account_state.nonce >= nonce ->
        throw({:error, "Nonce too small"})

      claim == nil ->
        throw({:error, "Name has not been claimed"})

      claim.owner != sender ->
        throw({:error, "Sender is not claim owner"})

      claim.status == :revoked ->
        throw({:error, "Claim is revoked"})

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
