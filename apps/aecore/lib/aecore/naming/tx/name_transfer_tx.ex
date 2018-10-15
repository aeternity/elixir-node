defmodule Aecore.Naming.Tx.NameTransferTx do
  @moduledoc """
  Module defining the NameTransfer transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Keys
  alias Aecore.Naming.NamingStateTree
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash

  require Logger

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the Transfer Transaction"
  @type payload :: %{
          hash: binary(),
          target: Keys.pubkey()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameTransferTx we have the naming subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the NameTransferTx Transaction type"
  @type t :: %NameTransferTx{
          hash: binary(),
          target: Keys.pubkey()
        }

  @doc """
  Definition of the NameTransferTx structure
  # Parameters
  - hash: hash of name to be transfered
  - target: target public key to transfer to
  """
  defstruct [:hash, :target]

  # Callbacks

  @spec init(payload()) :: NameTransferTx.t()
  def init(%{hash: %Identifier{} = identified_hash, target: %Identifier{} = identified_target}) do
    %NameTransferTx{hash: identified_hash, target: identified_target}
  end

  def init(%{hash: hash, target: target}) do
    identified_name_hash = Identifier.create_identity(hash, :name)
    identified_target = Identifier.create_identity(target, :account)
    %NameTransferTx{hash: identified_name_hash, target: identified_target}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(NameTransferTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%NameTransferTx{hash: %Identifier{value: hash}, target: target}, %DataTx{
        senders: senders
      }) do
    cond do
      byte_size(hash) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash))}"}

      !Keys.key_size_valid?(target) ->
        {:error, "#{__MODULE__}: target size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :naming

  @doc """
  Changes the naming state for claim transfers.
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameTransferTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        naming_state,
        _block_height,
        %NameTransferTx{target: %Identifier{value: target}, hash: %Identifier{value: hash}},
        _data_tx
      ) do
    claim_to_update = NamingStateTree.get(naming_state, hash)
    claim = %{claim_to_update | owner: target}
    updated_naming_chainstate = NamingStateTree.put(naming_state, hash, claim)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameTransferTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        naming_state,
        _block_height,
        %NameTransferTx{hash: %Identifier{value: hash}},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]}
      ) do
    account_state = AccountStateTree.get(accounts, sender)
    claim = NamingStateTree.get(naming_state, hash)

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
          NameTransferTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(NameTransferTx.t(), DataTx.t()) :: list()
  def encode_to_list(%NameTransferTx{hash: hash, target: target}, %DataTx{
        senders: [sender],
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Identifier.encode_to_binary(hash),
      Identifier.encode_to_binary(target),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        encoded_hash,
        encoded_recipient,
        fee,
        ttl
      ]) do
    with {:ok, hash} <- Identifier.decode_from_binary(encoded_hash),
         {:ok, recipient} <- Identifier.decode_from_binary(encoded_recipient) do
      payload = %NameTransferTx{hash: hash, target: recipient}

      DataTx.init_binary(
        NameTransferTx,
        payload,
        [encoded_sender],
        :binary.decode_unsigned(fee),
        :binary.decode_unsigned(nonce),
        :binary.decode_unsigned(ttl)
      )
    else
      {:error, _} = error -> error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
