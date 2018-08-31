defmodule Aecore.Oracle.Tx.OracleResponseTx do
  @moduledoc """
  Contains the transaction structure for oracle responses
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier

  @version 1

  @type payload :: %{
          query_id: binary(),
          response: String.t()
        }

  @type t :: %OracleResponseTx{
          query_id: binary(),
          response: String.t()
        }

  @type tx_type_state() :: Chainstate.oracles()

  defstruct [:query_id, :response]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: OracleResponseTx.t()
  def init(%{
        query_id: query_id,
        response: response
      }) do
    %OracleResponseTx{
      query_id: query_id,
      response: response
    }
  end

  @spec validate(OracleResponseTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%OracleResponseTx{query_id: query_id}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      byte_size(query_id) != get_query_id_size() ->
        {:error, "#{__MODULE__}: Wrong query_id size"}

      true ->
        :ok
    end
  end

  @spec get_query_id_size :: non_neg_integer()
  def get_query_id_size do
    Application.get_env(:aecore, :oracle_response_tx)[:query_id]
  end

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
        %OracleResponseTx{} = tx,
        data_tx,
        _context
      ) do
    sender = DataTx.main_sender(data_tx)
    interaction_objects = OracleStateTree.get_query(oracles, tx.query_id)
    query_fee = interaction_objects.fee

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, query_fee)
      end)

    updated_interaction_objects = %{
      interaction_objects
      | response: tx.response,
        expires: interaction_objects.response_ttl + block_height,
        has_response: true
    }

    updated_oracle_state = OracleStateTree.enter_query(oracles, updated_interaction_objects)

    {:ok, {updated_accounts_state, updated_oracle_state}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleResponseTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        oracles,
        _block_height,
        tx,
        data_tx,
        _context
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Sender: #{inspect(sender)} isn't a registered operator"}

      !is_binary(tx.response) ->
        {:error, "#{__MODULE__}: Invalid response data: #{inspect(tx.response)}"}

      !OracleStateTree.exists_query?(oracles, tx.query_id) ->
        {:error, "#{__MODULE__}: No query with the ID: #{inspect(tx.query_id)}"}

      OracleStateTree.get_query(oracles, tx.query_id).response != :undefined ->
        {:error, "#{__MODULE__}: Query already answered"}

      OracleStateTree.get_query(oracles, tx.query_id).oracle_address != sender ->
        {:error, "#{__MODULE__}: Query references a different oracle"}

      !is_minimum_fee_met?(tx, fee) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} too low"}

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
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(OracleResponseTx.t(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(tx, fee) do
    oracles = Chain.chain_state().oracles
    referenced_query_response_ttl = OracleStateTree.get_query(oracles, tx.query_id).response_ttl
    fee >= calculate_minimum_fee(referenced_query_response_ttl)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_response_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  def encode_to_list(%OracleResponseTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(datatx.nonce),
      tx.query_id,
      tx.response,
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        query_id,
        response,
        fee,
        ttl
      ]) do
    payload = %{
      query_id: query_id,
      response: response
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
