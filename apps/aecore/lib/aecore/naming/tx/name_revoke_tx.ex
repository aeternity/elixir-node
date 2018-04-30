defmodule Aecore.Naming.Tx.NameRevokeTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.Naming
  alias Aeutil.Hash
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
  def init(%{hash: hash}) do
    %NameRevokeTx{hash: hash}
  end

  @doc """
  Checks name hash byte size
  """
  @spec validate(NameRevokeTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameRevokeTx{hash: hash}) do
    if byte_size(hash) == Hash.get_hash_bytes_size() do
      :ok
    else
      {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash))}"}
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Revokes a previously claimed name for one account
  """
  @spec process_chainstate(
          SpendTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.tree(),
          tx_type_state()
        ) :: {AccountStateTree.tree(), tx_type_state()}
  def process_chainstate(
        %NameRevokeTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming_state
      ) do
    sender_account_state = Account.get_account_state(accounts, sender)

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
  @spec preprocess_check(
          SpendTx.t(),
          Wallet.pubkey(),
          AccountStateTree.tree(),
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
