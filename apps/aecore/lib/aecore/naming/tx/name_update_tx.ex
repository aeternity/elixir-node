defmodule Aecore.Naming.Tx.NameUpdateTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Naming
  alias Aecore.Structures.Account
  alias Aecore.Structures.AccountStateTree

  require Logger

  @typedoc "Expected structure for the Update Transaction"
  @type payload :: %{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameUpdateTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the NameUpdateTx Transaction type"
  @type t :: %NameUpdateTx{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @doc """
  Definition of Aecore NameUpdateTx structure

  ## Parameters
  - hash: hash of name to be updated
  - expire_by: expiration block of name update
  - client_ttl: ttl for client use
  - pointers: pointers from name update
  """
  defstruct [:hash, :expire_by, :client_ttl, :pointers]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameUpdateTx.t()
  def init(%{
        hash: hash,
        expire_by: expire_by,
        client_ttl: client_ttl,
        pointers: pointers
      }) do
    %NameUpdateTx{hash: hash, expire_by: expire_by, client_ttl: client_ttl, pointers: pointers}
  end

  @doc """
  Checks name format
  """
  @spec is_valid?(NameUpdateTx.t()) :: boolean()
  def is_valid?(%NameUpdateTx{
        hash: _hash,
        expire_by: _expire_by,
        client_ttl: client_ttl,
        pointers: _pointers
      }) do
    # TODO validate hash byte size
    # TODO check pointers format
    valid_pointers_format = true
    valid_client_ttl = client_ttl <= Naming.get_client_ttl_limit()
    valid_client_ttl && valid_pointers_format
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          NameUpdateTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %NameUpdateTx{} = tx,
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
      | pointers: [tx.pointers],
        expires: tx.expire_by,
        ttl: tx.client_ttl
    }

    updated_naming_chainstate = Map.put(naming_state, tx.hash, claim)

    {updated_accounts_chainstate, updated_naming_chainstate}
  end

  @doc """
  Checks whether all the data is valid according to the NameUpdateTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          NameUpdateTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check!(tx, account_state, sender, fee, nonce, block_height, naming_state) do
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

      tx.expire_by <= block_height ->
        throw({:error, "Name expiration is now or in the past"})

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
end
