defmodule Aecore.Naming.Tx.NameRevokeTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.{Naming, NamingStateTree}
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx

  require Logger

  @typedoc "Expected structure for the Revoke Transaction"
  @type payload :: %{
          hash: binary()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameRevokeTx we have the naming subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

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

  @spec init(payload()) :: t()
  def init(%{hash: hash}) do
    %NameRevokeTx{hash: hash}
  end

  @doc """
  Checks name hash byte size
  """
  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameRevokeTx{hash: hash}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      byte_size(hash) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash))}"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Revokes a previously claimed name for one account
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        naming_state,
        block_height,
        %NameRevokeTx{} = tx,
        _data_tx
      ) do
    claim_to_update = NamingStateTree.get(naming_state, tx.hash)

    claim = %{
      claim_to_update
      | status: :revoked,
        expires: block_height + Naming.get_revoke_expiration_ttl()
    }

    updated_naming_chainstate = NamingStateTree.put(naming_state, tx.hash, claim)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Checks whether all the data is valid according to the NameRevokeTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        naming_state,
        _block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)
    account_state = AccountStateTree.get(accounts, sender)
    claim = NamingStateTree.get(naming_state, tx.hash)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}

      claim == :none ->
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

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end
end
