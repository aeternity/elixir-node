defmodule Aecore.Naming.Structures.NameRevokeTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.NameRevokeTx
  alias Aecore.Naming.Naming
  alias Aecore.Naming.NameUtil
  alias Aecore.Structures.Account

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
        account_naming = Map.get(naming_state, sender, Naming.empty())

        claim_to_revoke =
          Enum.find(account_naming.claims, fn claim ->
            tx.hash == NameUtil.normalized_namehash!(claim.name)
          end)

        filtered_claims =
          Enum.filter(account_naming.claims, fn claim ->
            claim.name != claim_to_revoke.name
          end)

        updated_naming_chainstate =
          Map.put(naming_state, sender, %{account_naming | claims: filtered_claims})

        # only revoke if actually found and removed for this account
        updated_naming_chainstate_withrevokes =
          case claim_to_revoke do
            %{name: name} ->
              if NameUtil.normalized_namehash!(name) == tx.hash do
                naming_revoked = Map.get(updated_naming_chainstate, :revoked, [])
                updated_revokes = [%{tx.hash => block_height} | naming_revoked]
                Map.put(updated_naming_chainstate, :revoked, updated_revokes)
              else
                updated_naming_chainstate
              end

            _ ->
              updated_naming_chainstate
          end

        {updated_accounts_chainstate, updated_naming_chainstate_withrevokes}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the NameRevokeTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          NameRevokeTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check(tx, account_state, sender, fee, nonce, _block_height, naming_state) do
    account_naming = Map.get(naming_state, sender, Naming.empty())

    claimed =
      Enum.find(account_naming.claims, fn claim ->
        NameUtil.normalized_namehash!(claim.name) == tx.hash
      end)

    naming_revoked = Map.get(naming_state, :revoked, [])
    revoked = Enum.find(naming_revoked, fn {revoked, _height} -> revoked == tx.hash end)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      claimed == nil ->
        {:error, "Name has not been claimed"}

      revoked != nil ->
        {:error, "Name has already been revoked"}

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
