defmodule Aecore.Naming.Tx.NamePreClaimTx do
  @moduledoc """
  Module defining the NamePreClaim transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.{NameCommitment, NamingStateTree}
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aeutil.Hash

  require Logger

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @type commitment_hash :: binary()

  @typedoc "Expected structure for the Pre Claim Transaction"
  @type payload :: %{
          commitment: commitment_hash()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NamePreClaimTx we don't have a subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the NamePreClaim Transaction type"
  @type t :: %NamePreClaimTx{
          commitment: commitment_hash()
        }

  @doc """
  Definition of the NamePreClaimTx structure
  # Parameters
  - commitment: hash of the commitment for name claiming
  """
  defstruct [:commitment]

  # Callbacks

  @spec init(payload()) :: NamePreClaimTx.t()
  def init(%{commitment: %Identifier{} = identified_commitment}) do
    %NamePreClaimTx{commitment: identified_commitment}
  end

  def init(%{commitment: commitment}) do
    identified_commitment = Identifier.create_identity(commitment, :commitment)
    %NamePreClaimTx{commitment: identified_commitment}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(NamePreClaimTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%NamePreClaimTx{commitment: commitment}, %DataTx{senders: senders}) do
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

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :naming

  @doc """
  Pre claims a name for one account.
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NamePreClaimTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        naming_state,
        block_height,
        %NamePreClaimTx{commitment: %Identifier{value: value}},
        %DataTx{senders: [%Identifier{value: sender}]}
      ) do
    commitment_expires = block_height + GovernanceConstants.pre_claim_ttl()

    commitment = NameCommitment.create(value, sender, block_height, commitment_expires)

    updated_naming_chainstate = NamingStateTree.put(naming_state, value, commitment)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NamePreClaimTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(accounts, _naming_state, _block_height, _tx, %DataTx{
        fee: fee,
        senders: [%Identifier{value: sender}]
      }) do
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
          NamePreClaimTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(%SignedTx{data: %DataTx{fee: fee}}) do
    fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec encode_to_list(NamePreClaimTx.t(), DataTx.t()) :: list()
  def encode_to_list(%NamePreClaimTx{commitment: commitment}, %DataTx{
        senders: [sender],
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Identifier.encode_to_binary(commitment),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [encoded_sender, nonce, encoded_commitment, fee, ttl]) do
    case Identifier.decode_from_binary(encoded_commitment) do
      {:ok, commitment} ->
        payload = %NamePreClaimTx{commitment: commitment}

        DataTx.init_binary(
          NamePreClaimTx,
          payload,
          [encoded_sender],
          :binary.decode_unsigned(fee),
          :binary.decode_unsigned(nonce),
          :binary.decode_unsigned(ttl)
        )

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
