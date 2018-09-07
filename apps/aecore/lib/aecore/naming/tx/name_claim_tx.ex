defmodule Aecore.Naming.Tx.NameClaimTx do
  @moduledoc """
  Module defining the NameClaim transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.{Name, NameUtil, NameCommitment, NamingStateTree}
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Chain.Identifier
  alias Aecore.Governance.GovernanceConstants

  require Logger

  @version 1

  @typedoc "Expected structure for the Claim Transaction"
  @type payload :: %{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameClaimTx we have the naming subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %NameClaimTx{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @doc """
  Definition of the NameClaimTx structure
  # Parameters
  - name: name to be claimed
  - name_salt: salt that the name was pre-claimed with
  """
  defstruct [:name, :name_salt]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameClaimTx.t()
  def init(%{name: name, name_salt: name_salt}) do
    %NameClaimTx{name: name, name_salt: name_salt}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(NameClaimTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameClaimTx{name: name, name_salt: name_salt}, data_tx) do
    validate_name = NameUtil.normalize_and_validate_name(name)
    senders = DataTx.senders(data_tx)

    cond do
      validate_name |> elem(0) == :error ->
        {:error, "#{__MODULE__}: #{validate_name |> elem(1)}: #{inspect(name)}"}

      !is_integer(name_salt) ->
        {:error,
         "#{__MODULE__}: Name salt is not correct: #{inspect(name_salt)}, should be integer"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
  def get_chain_state_name, do: :naming

  @doc """
  Claims a name for one account after it was pre-claimed.
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameClaimTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        naming_state,
        block_height,
        %NameClaimTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    {:ok, pre_claim_commitment} = NameCommitment.commitment_hash(tx.name, tx.name_salt)
    {:ok, claim_hash} = NameUtil.normalized_namehash(tx.name)
    claim = Name.create(claim_hash, sender, block_height)

    updated_naming_chainstate =
      naming_state
      |> NamingStateTree.delete(pre_claim_commitment)
      |> NamingStateTree.put(claim_hash, claim)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameClaimTx.t(),
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

    {:ok, pre_claim_commitment} = NameCommitment.commitment_hash(tx.name, tx.name_salt)
    pre_claim = NamingStateTree.get(naming_state, pre_claim_commitment)

    {:ok, claim_hash} = NameUtil.normalized_namehash(tx.name)
    claim = NamingStateTree.get(naming_state, claim_hash)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}

      pre_claim == :none ->
        {:error, "#{__MODULE__}: Name has not been pre-claimed: #{inspect(pre_claim)}"}

      pre_claim.owner != sender ->
        {:error,
         "#{__MODULE__}: Sender is not pre-claim owner: #{inspect(pre_claim.owner)}, #{
           inspect(sender)
         }"}

      claim != :none ->
        {:error, "#{__MODULE__}: Name has aleady been claimed: #{inspect(claim)}"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          NameClaimTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    total_fee = fee + GovernanceConstants.name_claim_burned_fee()
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, total_fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%NameClaimTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      tx.name,
      :binary.encode_unsigned(tx.name_salt),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

  def decode_from_list(@version, [encoded_sender, nonce, name, name_salt, fee, ttl]) do
    payload = %NameClaimTx{name: name, name_salt: :binary.decode_unsigned(name_salt)}

    DataTx.init_binary(
      NameClaimTx,
      payload,
      [encoded_sender],
      :binary.decode_unsigned(fee),
      :binary.decode_unsigned(nonce),
      :binary.decode_unsigned(ttl)
    )
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
