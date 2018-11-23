defmodule Aecore.Oracle.Tx.OracleResponseTx do
  @moduledoc """
  Module defining the OracleResponse transaction
  """

  use Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Oracle.Oracle
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the OracleResponseTx Transaction"
  @type payload :: %{
          query_id: binary(),
          response: String.t(),
          response_ttl: Oracle.relative_ttl()
        }

  @typedoc "Structure of the OracleResponseTx Transaction type"
  @type t :: %OracleResponseTx{
          query_id: binary(),
          response: String.t(),
          response_ttl: Oracle.relative_ttl()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.oracles()

  defstruct [:query_id, :response, :response_ttl]

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :oracle

  @spec init(payload()) :: OracleResponseTx.t()
  def init(%{
        query_id: query_id,
        response: response,
        response_ttl: response_ttl
      }) do
    %OracleResponseTx{
      query_id: query_id,
      response: response,
      response_ttl: response_ttl
    }
  end

  @spec validate(OracleResponseTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%OracleResponseTx{query_id: query_id}, %DataTx{
        senders: [%Identifier{value: oracle_id} | _] = senders
      }) do
    tree_query_id = oracle_id <> query_id

    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      byte_size(tree_query_id) != get_query_id_size() ->
        {:error, "#{__MODULE__}: Wrong query_id size"}

      true ->
        :ok
    end
  end

  @spec get_query_id_size :: non_neg_integer()
  def get_query_id_size do
    Application.get_env(:aecore, :oracle_response_tx)[:query_id]
  end

  @doc """
  Enters a response for a certain query in the oracle state tree
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleResponseTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleResponseTx{query_id: query_id, response: response},
        %DataTx{senders: [%Identifier{value: sender}]},
        _context
      ) do
    tree_query_id = sender <> query_id
    interaction_objects = OracleStateTree.get_query(oracles, tree_query_id)
    query_fee = interaction_objects.fee

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, query_fee)
      end)

    updated_interaction_objects = %{
      interaction_objects
      | response: response,
        expires: interaction_objects.response_ttl.ttl + block_height,
        has_response: true
    }

    updated_oracle_state = OracleStateTree.enter_query(oracles, updated_interaction_objects)

    {:ok, {updated_accounts_state, updated_oracle_state}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleResponseTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        oracles,
        _block_height,
        %OracleResponseTx{response: response, query_id: query_id, response_ttl: response_ttl},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]},
        _context
      ) do
    tree_query_id = sender <> query_id
    query = OracleStateTree.get_query(oracles, tree_query_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Sender: #{inspect(sender)} isn't a registered operator"}

      !is_binary(response) ->
        {:error, "#{__MODULE__}: Invalid response data: #{inspect(response)}"}

      !OracleStateTree.exists_query?(oracles, tree_query_id) ->
        {:error, "#{__MODULE__}: No query with the ID: #{inspect(tree_query_id)}"}

      query.response != :undefined ->
        {:error, "#{__MODULE__}: Query already answered"}

      query.response_ttl != response_ttl ->
        {:error,
         "#{__MODULE__}: Invalid response_ttl #{inspect(response_ttl)}, expected #{
           inspect(query.response_ttl)
         }"}

      query.oracle_address != sender ->
        {:error, "#{__MODULE__}: Query references a different oracle"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          OracleResponseTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(
        %DataTx{
          payload: %OracleResponseTx{query_id: query_id},
          senders: [%Identifier{value: sender}],
          fee: fee
        },
        oracles_tree,
        _block_height
      ) do
    tree_query_id = sender <> query_id

    ttl_fee = fee - GovernanceConstants.oracle_response_base_fee()

    referenced_query_response_ttl =
      OracleStateTree.get_query(oracles_tree, tree_query_id).response_ttl

    ttl_fee >= Oracle.calculate_minimum_fee(referenced_query_response_ttl.ttl)
  end

  @spec encode_to_list(OracleResponseTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %OracleResponseTx{query_id: query_id, response: response, response_ttl: response_ttl},
        %DataTx{
          senders: [sender],
          nonce: nonce,
          fee: fee,
          ttl: ttl
        }
      ) do
    encoded_ttl_type = Serialization.encode_ttl_type(response_ttl)

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      query_id,
      response,
      encoded_ttl_type,
      :binary.encode_unsigned(response_ttl.ttl),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        query_id,
        response,
        encoded_response_ttl_type,
        response_ttl_value,
        fee,
        ttl
      ]) do
    response_ttl_type = Serialization.decode_ttl_type(encoded_response_ttl_type)

    payload = %{
      query_id: query_id,
      response: response,
      response_ttl: %{ttl: :binary.decode_unsigned(response_ttl_value), type: response_ttl_type}
    }

    DataTx.init_binary(
      OracleResponseTx,
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
