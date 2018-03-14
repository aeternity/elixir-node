defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """
  alias __MODULE__
  alias Aecore.Txs.Pool.Worker, as: Pool

  @type t :: %SpendTx{
          from_acc: binary(),
          to_acc: binary(),
          value: non_neg_integer(),
          nonce: non_neg_integer(),
          fee: non_neg_integer(),
          lock_time_block: non_neg_integer()
        }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - nonce: A random integer generated on initialisation of a transaction.Must be unique
  - from_acc: From account is the public address of one account originating the transaction
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of a transaction
  """
  defstruct [:from_acc, :to_acc, :value, :nonce, :fee, :lock_time_block]
  use ExConstructor

  @spec create(
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SpendTx.t()}
  def create(from_acc, to_acc, value, nonce, fee, lock_time_block \\ 0) do
    {:ok,
     %SpendTx{
       from_acc: from_acc,
       to_acc: to_acc,
       value: value,
       nonce: nonce,
       fee: fee,
       lock_time_block: lock_time_block
     }}
  end

  @spec is_minimum_fee_met?(SignedTx.t(), :miner | :pool) :: boolean()
  def is_minimum_fee_met?(tx, identifier) do
    tx_size_bytes = Pool.get_tx_size_bytes(tx)

    bytes_per_token =
      case identifier do
        :pool ->
          Application.get_env(:aecore, :tx_data)[:pool_fee_bytes_per_token]

        :miner ->
          Application.get_env(:aecore, :tx_data)[:miner_fee_bytes_per_token]
      end

    tx.data.fee >= Float.floor(tx_size_bytes / bytes_per_token)
  end
end
