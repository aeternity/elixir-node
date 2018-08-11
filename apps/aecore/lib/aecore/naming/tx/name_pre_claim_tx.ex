defmodule Aecore.Naming.Tx.NamePreClaimTx do
  @moduledoc """
  Aecore structure of naming pre claim data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.{NameCommitment, NamingStateTree}
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Identifier
  alias Aecore.Governance.GovernanceConstants

  require Logger

  @version 1

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
  def init(%{commitment: %Identifier{} = identified_commitment} = _payload) do
    %NamePreClaimTx{commitment: identified_commitment}
  end

  def init(%{commitment: commitment} = _payload) do
    identified_commitment = Identifier.create_identity(commitment, :commitment)
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
    sender = DataTx.main_sender(data_tx)

    commitment_expires = block_height + GovernanceConstants.pre_claim_ttl()

    commitment =
      NameCommitment.create(tx.commitment.value, sender, block_height, commitment_expires)

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

  def encode_to_list(%NamePreClaimTx{} = tx, %DataTx{} = datatx) do
    [
      @version,
      Identifier.encode_list_to_binary(datatx.senders),
      datatx.nonce,
      Identifier.encode_to_binary(tx.commitment),
      datatx.fee,
      datatx.ttl
    ]
  end

  def decode_from_list(@version, [encoded_senders, nonce, encoded_commitment, fee, ttl]) do
    case Identifier.decode_from_binary(encoded_commitment) do
      {:ok, commitment} ->
        payload = %NamePreClaimTx{commitment: commitment}

        DataTx.init_binary(
          NamePreClaimTx,
          payload,
          encoded_senders,
          fee,
          nonce,
          ttl
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
