defmodule Aecore.Oracle.Tx.OracleExtendTx do
  @moduledoc """
  Module defining the OracleExtend transaction
  """

  use Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization

  require Logger

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the OracleExtend Transaction"
  @type payload :: %{
          ttl: Oracle.ttl()
        }

  @typedoc "Structure of the OracleExtend Transaction type"
  @type t :: %OracleExtendTx{
          ttl: Oracle.ttl()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.oracles()

  defstruct [:ttl]

  @spec get_chain_state_name() :: atom()
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: OracleExtendTx.t()
  def init(%{ttl: ttl}) do
    %OracleExtendTx{ttl: ttl}
  end

  @spec validate(OracleExtendTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%OracleExtendTx{ttl: ttl}, %DataTx{senders: senders}) do
    cond do
      ttl <= 0 ->
        {:error, "#{__MODULE__}: Negative ttl: #{inspect(ttl)} in OracleExtendTx"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @doc """
  Adds the TTL to the current oracle object expiry height
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        _block_height,
        %OracleExtendTx{ttl: %{ttl: ttl}},
        %DataTx{senders: [%Identifier{value: sender}]}
      ) do
    registered_oracle = OracleStateTree.get_oracle(oracles, sender)

    updated_registered_oracle = Map.update!(registered_oracle, :expires, &(&1 + ttl))
    updated_oracle_state = OracleStateTree.enter_oracle(oracles, updated_registered_oracle)

    {:ok, {accounts, updated_oracle_state}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(accounts, oracles, _block_height, %OracleExtendTx{}, %DataTx{
        senders: [%Identifier{value: sender}],
        fee: fee
      }) do
    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Account - #{inspect(sender)}, isn't a registered operator"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(
        %DataTx{fee: fee, payload: %OracleExtendTx{ttl: %{ttl: ttl}}},
        _chain_state,
        _block_height
      ) do
    ttl_fee = fee - GovernanceConstants.oracle_extend_base_fee()
    ttl_fee >= Oracle.calculate_minimum_fee(ttl)
  end

  @spec encode_to_list(OracleExtendTx.t(), DataTx.t()) :: list()
  def encode_to_list(%OracleExtendTx{ttl: %{ttl: extend_ttl_value} = extend_ttl}, %DataTx{
        senders: [sender],
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      Serialization.encode_ttl_type(extend_ttl),
      :binary.encode_unsigned(extend_ttl_value),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [encoded_sender, nonce, ttl_type, ttl_value, fee, ttl]) do
    payload = %{
      ttl: %{
        ttl: :binary.decode_unsigned(ttl_value),
        type: Serialization.decode_ttl_type(ttl_type)
      }
    }

    DataTx.init_binary(
      OracleExtendTx,
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
