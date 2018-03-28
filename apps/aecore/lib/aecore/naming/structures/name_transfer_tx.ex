defmodule Aecore.Naming.Structures.NameTransferTx do
  @moduledoc """
  Aecore structure of naming transfer.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Structures.NameTransferTx
  alias Aecore.Naming.Naming
  alias Aecore.Naming.NameUtil
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
        naming
      ) do
    case preprocess_check(tx, accounts[sender], sender, fee, nonce, block_height, naming) do
      :ok ->
        new_senderount_state =
          accounts[sender]
          |> deduct_fee(fee)
          |> Account.transaction_out_nonce_update(nonce)

        updated_accounts_chainstate = Map.put(accounts, sender, new_senderount_state)
        account_naming = Map.get(naming, sender, Naming.empty())

        claim_to_update =
          Enum.find(account_naming.claims, fn claim ->
            tx.hash == NameUtil.normalized_namehash!(claim.name)
          end)

        filtered_claims =
          Enum.filter(account_naming.claims, fn claim ->
            claim.name != claim_to_update.name
          end)

        target_account_naming = Map.get(naming, tx.target, Naming.empty())
        target_updated_naming_claims = [claim_to_update | target_account_naming.claims]

        updated_naming_chainstate =
          naming
          |> Map.put(sender, %{account_naming | claims: filtered_claims})
          |> Map.put(tx.target, %{account_naming | claims: target_updated_naming_claims})

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
  def preprocess_check(tx, account_state, sender, fee, nonce, _block_height, naming) do
    account_naming = Map.get(naming, sender, Naming.empty())

    claimed =
      Enum.find(account_naming.claims, fn claim ->
        NameUtil.normalized_namehash!(claim.name) == tx.hash
      end)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      claimed == nil ->
        {:error, "Name has not been claimed"}

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
