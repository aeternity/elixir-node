defmodule Aecore.Naming.Tx.NameTransferTx do
  @moduledoc """
  Aecore structure of naming transfer.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.{Naming, NamingStateTree}
  alias Aeutil.Hash
  alias Aecore.Keys
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

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
  Definition of Aecore NameTransferTx structure
  ## Parameters
  - hash: hash of name to be transfered
  - target: target public key to transfer to
  """
  defstruct [:hash, :target]
  use ExConstructor

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
  Checks target and hash byte sizes
  """
  @spec validate(NameTransferTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameTransferTx{hash: hash, target: target}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      byte_size(hash.value) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash))}"}

      !Keys.key_size_valid?(target) ->
        {:error, "#{__MODULE__}: target size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: Naming.chain_state_name()
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
        %NameTransferTx{} = tx,
        _data_tx
      ) do
    claim_to_update = NamingStateTree.get(naming_state, tx.hash.value)
    claim = %{claim_to_update | owner: tx.target}
    updated_naming_chainstate = NamingStateTree.put(naming_state, tx.hash.value, claim)

    {:ok, {accounts, updated_naming_chainstate}}
  end

  @doc """
  Checks whether all the data is valid according to the NameTransferTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameTransferTx.t(),
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
    claim = NamingStateTree.get(naming_state, tx.hash.value)

    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - fee)}"}

      claim == :none ->
        {:error, "#{__MODULE__}: Name has not been claimed: #{inspect(claim)}"}

      claim.owner.value != sender ->
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
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%NameTransferTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      Identifier.encode_to_binary(tx.hash),
      Identifier.encode_to_binary(tx.target),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

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
