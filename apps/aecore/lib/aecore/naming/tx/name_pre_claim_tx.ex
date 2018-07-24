defmodule Aecore.Naming.Tx.NamePreClaimTx do
  @moduledoc """
  Aecore structure of naming pre claim data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.{Naming, NamingStateTree}
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Identifier
  alias Aecore.Governance.GovernanceConstants

  require Logger

  @type commitment_hash :: binary()

  @typedoc "Expected structure for the Pre Claim Transaction"
  @type payload :: %{
          commitment: commitment_hash()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NamePreClaimTx we don't have a subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %NamePreClaimTx{
          commitment: commitment_hash()
        }

  @doc """
  Definition of Aecore NamePreClaimTx structure
  ## Parameters
  - commitment: hash of the commitment for name claiming
  """
  defstruct [:commitment]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: t()
  def init(%{commitment: commitment} = _payload) do
    {:ok, identified_commitment} = Identifier.create_identity(commitment, :commitment)

    %NamePreClaimTx{commitment: identified_commitment}
  end

  @doc """
  Checks commitment hash byte size
  """
  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%NamePreClaimTx{commitment: commitment}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      byte_size(commitment.value) != Hash.get_hash_bytes_size() ->
        {:error,
         "#{__MODULE__}: Commitment bytes size not correct: #{inspect(byte_size(commitment))}"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Pre claims a name for one account.
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
        %NamePreClaimTx{} = tx,
        data_tx
      ) do
    [identified_sender] = data_tx.senders

    commitment_expires = block_height + GovernanceConstants.pre_claim_ttl()

    commitment =
      Naming.create_commitment(
        tx.commitment.value,
        identified_sender,
        block_height,
        commitment_expires
      )

    updated_naming_chainstate = NamingStateTree.put(naming_state, tx.commitment.value, commitment)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Checks whether all the data is valid according to the NamePreClaimTx requirements,
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
        _naming_state,
        _block_height,
        _tx,
        data_tx
      ) do
    fee = DataTx.fee(data_tx)
    sender = DataTx.main_sender(data_tx)
    account_state = AccountStateTree.get(accounts, sender)

    if account_state.balance - fee >= 0 do
      :ok
    else
      {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}
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
