defmodule Aecore.Oracle.Tx.OracleExtendTx do
  @moduledoc """
  Contains the transaction structure for oracle extensions
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

  @type payload :: %{
          ttl: non_neg_integer()
        }

  @type t :: %OracleExtendTx{
          ttl: non_neg_integer()
        }

  @type tx_type_state() :: Chainstate.oracles()

  defstruct [:ttl]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: t()
  def init(%{ttl: ttl}) do
    %OracleExtendTx{ttl: ttl}
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%OracleExtendTx{ttl: ttl}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      ttl <= 0 ->
        {:error, "#{__MODULE__}: Negative ttl: #{inspect(ttl)} in OracleExtendTx"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        _block_height,
        %OracleExtendTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    registered_oracle = OracleStateTree.get_oracle(oracles, sender)

    updated_registered_oracle = Map.update!(registered_oracle, :expires, &(&1 + tx.ttl))
    updated_oracle_state = OracleStateTree.enter_oracle(oracles, updated_registered_oracle)

    {:ok, {accounts, updated_oracle_state}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        oracles,
        _block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Account - #{inspect(sender)}, isn't a registered operator"}

      fee < calculate_minimum_fee(tx.ttl) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} is too low"}

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

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  def encode_to_list(%OracleExtendTx{} = tx, %DataTx{} = datatx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_list_to_binary(datatx.senders),
      :binary.encode_unsigned(datatx.nonce),
      :binary.encode_unsigned(tx.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

  def decode_from_list(@version, [encoded_senders, nonce, ttl_value, fee, ttl]) do
    payload = %{
      ttl: :binary.decode_unsigned(ttl_value)
    }

    DataTx.init_binary(
      OracleExtendTx,
      payload,
      encoded_senders,
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
