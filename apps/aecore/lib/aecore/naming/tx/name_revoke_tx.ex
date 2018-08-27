defmodule Aecore.Naming.Tx.NameRevokeTx do
  @moduledoc """
  Aecore structure of naming Update.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.{Naming, NamingStateTree}
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Governance.GovernanceConstants
  alias Aeutil.Hash

  require Logger

  @version 1

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
    name_hash =
      case hash do
        %Identifier{} ->
          if validate_identifier(hash) == true do
            hash
          else
            {:error,
             "#{__MODULE__}: Invalid specified type: #{inspect(hash.type)}, for given data: #{
               inspect(hash.value)
             }"}
          end

        non_identfied_name_hash ->
          Identifier.create_identity(non_identfied_name_hash, :name)
      end

    %NameRevokeTx{hash: name_hash}
  end

  @doc """
  Checks name hash byte size
  """
  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%NameRevokeTx{hash: hash}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      byte_size(hash.value) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: hash bytes size not correct: #{inspect(byte_size(hash.value))}"}

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
    claim_to_update = NamingStateTree.get(naming_state, tx.hash.value)

    claim = %{
      claim_to_update
      | status: :revoked,
        expires: block_height + GovernanceConstants.revoke_expiration_ttl()
    }

    updated_naming_chainstate = NamingStateTree.put(naming_state, tx.hash.value, claim)

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
    claim = NamingStateTree.get(naming_state, tx.hash.value)

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

  @spec validate_identifier(Identifier.t()) :: boolean()
  defp validate_identifier(%Identifier{} = id) do
    Identifier.create_identity(id.value, :name) == id
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%NameRevokeTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      Identifier.encode_to_binary(tx.hash),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

  def decode_from_list(@version, [encoded_sender, nonce, encoded_hash, fee, ttl]) do
    case Identifier.decode_from_binary(encoded_hash) do
      {:ok, hash} ->
        payload = %NameRevokeTx{hash: hash}

        DataTx.init_binary(
          NameRevokeTx,
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
