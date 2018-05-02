defmodule Aecore.Naming.Tx.NameUpdateTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Naming
  alias Aeutil.Hash
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

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
  @spec validate(NameUpdateTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameUpdateTx{
        hash: hash,
        expire_by: _expire_by,
        client_ttl: client_ttl,
        pointers: _pointers
      }) do
    cond do
      client_ttl > Naming.get_client_ttl_limit() ->
        {:error, "#{__MODULE__}: Client ttl is to high: #{inspect(client_ttl)}"}

      byte_size(hash) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: Hash bytes size not correct: #{inspect(byte_size(hash))}"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate(
          NameUpdateTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.accounts_state(),
          tx_type_state()
        ) :: {AccountStateTree.accounts_state(), tx_type_state()}
  def process_chainstate(
        %NameUpdateTx{} = tx,
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
  @spec preprocess_check(
          NameUpdateTx.t(),
          Wallet.pubkey(),
          AccountStateTree.accounts_state(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _nonce, block_height, naming_state) do
    claim = Map.get(naming_state, tx.hash)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}

      claim == nil ->
        {:error, "#{__MODULE__}: Name has not been claimed: #{inspect(claim)}"}

      claim.owner != sender ->
        {:error,
         "#{__MODULE__}: Sender is not claim owner: #{inspect(claim.owner)}, #{inspect(sender)}"}

      tx.expire_by <= block_height ->
        {:error,
         "#{__MODULE__}: Name expiration is now or in the past: #{inspect(tx.expire_by)}, #{
           inspect(block_height)
         }"}

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
