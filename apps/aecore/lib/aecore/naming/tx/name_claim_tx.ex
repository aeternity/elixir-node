defmodule Aecore.Naming.Tx.NameClaimTx do
  @moduledoc """
  Module defining the NameClaim transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.{Name, NameUtil, NameCommitment, NamingStateTree}
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Tx.{DataTx, SignedTx}

  require Logger

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the Claim Transaction"
  @type payload :: %{
          name: String.t(),
          name_salt: Name.salt()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameClaimTx we have the naming subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the NameClaimTx Transaction type"
  @type t :: %NameClaimTx{
          name: String.t(),
          name_salt: Name.salt()
        }

  @doc """
  Definition of the NameClaimTx structure
  # Parameters
  - name: name to be claimed
  - name_salt: salt that the name was pre-claimed with
  """
  defstruct [:name, :name_salt]

  # Callbacks

  @spec init(payload()) :: NameClaimTx.t()
  def init(%{name: name, name_salt: name_salt}) do
    %NameClaimTx{name: name, name_salt: name_salt}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(NameClaimTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%NameClaimTx{name: name, name_salt: name_salt}, %DataTx{senders: senders}) do
    validate_name = NameUtil.normalize_and_validate_name(name)

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

  @spec get_chain_state_name :: atom()
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
        %NameClaimTx{name: name, name_salt: name_salt},
        %DataTx{senders: [%Identifier{value: sender}]}
      ) do
    {:ok, pre_claim_commitment} = NameCommitment.commitment_hash(name, name_salt)
    {:ok, claim_hash} = NameUtil.normalized_namehash(name)
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
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        naming_state,
        _block_height,
        %NameClaimTx{name: name, name_salt: name_salt},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]}
      ) do
    account_state = AccountStateTree.get(accounts, sender)

    {:ok, pre_claim_commitment} = NameCommitment.commitment_hash(name, name_salt)
    pre_claim = NamingStateTree.get(naming_state, pre_claim_commitment)

    {:ok, claim_hash} = NameUtil.normalized_namehash(name)
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
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    total_fee = fee + GovernanceConstants.name_claim_burned_fee()
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, total_fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(%SignedTx{data: %DataTx{fee: fee}}) do
    fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(NameClaimTx.t(), DataTx.t()) :: list()
  def encode_to_list(%NameClaimTx{name: name, name_salt: name_salt}, %DataTx{
        senders: [sender],
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      name,
      :binary.encode_unsigned(name_salt),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
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
