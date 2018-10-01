defmodule Aecore.Naming.Tx.NameUpdateTx do
  @moduledoc """
  Module defining the NameUpdate transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Naming.NamingStateTree
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aeutil.Hash

  require Logger

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the Update Transaction"
  @type payload :: %{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameUpdateTx we have the naming subdomain chainstate."
  @type tx_type_state() :: Chainstate.naming()

  @typedoc "Structure of the NameUpdateTx Transaction type"
  @type t :: %NameUpdateTx{
          hash: binary(),
          expire_by: non_neg_integer(),
          client_ttl: non_neg_integer(),
          pointers: String.t()
        }

  @doc """
  Definition of the NameUpdateTx structure
  # Parameters
  - hash: hash of name to be updated
  - expire_by: expiration block of name update
  - client_ttl: ttl for client use
  - pointers: pointers from name update
  """
  defstruct [:hash, :expire_by, :client_ttl, :pointers]

  # Callbacks

  @spec init(payload()) :: NameUpdateTx.t()
  def init(%{
        hash: %Identifier{} = identified_hash,
        expire_by: expire_by,
        client_ttl: client_ttl,
        pointers: pointers
      }) do
    %NameUpdateTx{
      hash: identified_hash,
      expire_by: expire_by,
      client_ttl: client_ttl,
      pointers: pointers
    }
  end

  def init(%{
        hash: hash,
        expire_by: expire_by,
        client_ttl: client_ttl,
        pointers: pointers
      }) do
    identified_name_hash = Identifier.create_identity(hash, :name)

    %NameUpdateTx{
      hash: identified_name_hash,
      expire_by: expire_by,
      client_ttl: client_ttl,
      pointers: pointers
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(NameUpdateTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %NameUpdateTx{
          hash: %Identifier{value: hash},
          expire_by: _expire_by,
          client_ttl: client_ttl,
          pointers: _pointers
        },
        %DataTx{senders: senders}
      ) do
    cond do
      client_ttl > GovernanceConstants.client_ttl_limit() ->
        {:error, "#{__MODULE__}: Client ttl is to high: #{inspect(client_ttl)}"}

      byte_size(hash) != Hash.get_hash_bytes_size() ->
        {:error, "#{__MODULE__}: Hash bytes size not correct: #{inspect(byte_size(hash))}"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          NameUpdateTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        naming_state,
        block_height,
        %NameUpdateTx{
          hash: %Identifier{value: hash},
          pointers: pointers,
          expire_by: expire_by,
          client_ttl: client_ttl
        },
        _data_tx
      ) do
    claim_to_update = NamingStateTree.get(naming_state, hash)

    claim = %{
      claim_to_update
      | pointers: pointers,
        expires: client_ttl + block_height,
        client_ttl: expire_by
    }

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
          NameUpdateTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        naming_state,
        block_height,
        %NameUpdateTx{hash: %Identifier{value: hash}, expire_by: expire_by},
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

      expire_by <= block_height ->
        {:error,
         "#{__MODULE__}: Name expiration is now or in the past: #{inspect(expire_by)}, #{
           inspect(block_height)
         }"}

      claim.status == :revoked ->
        {:error, "#{__MODULE__}: Claim is revoked: #{inspect(claim.status)}"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          NameUpdateTx.t(),
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

  @spec encode_to_list(NameUpdateTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %NameUpdateTx{
          hash: hash,
          client_ttl: client_ttl,
          pointers: pointers,
          expire_by: expire_by
        },
        %DataTx{senders: [sender], nonce: nonce, fee: fee, ttl: ttl}
      ) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Identifier.encode_to_binary(hash),
      :binary.encode_unsigned(client_ttl),
      pointers,
      :binary.encode_unsigned(expire_by),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        encoded_hash,
        client_ttl,
        pointers,
        expire_by,
        fee,
        ttl
      ]) do
    case Identifier.decode_from_binary(encoded_hash) do
      {:ok, hash} ->
        payload = %NameUpdateTx{
          client_ttl: :binary.decode_unsigned(client_ttl),
          expire_by: :binary.decode_unsigned(expire_by),
          hash: hash,
          pointers: pointers
        }

        DataTx.init_binary(
          NameUpdateTx,
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
