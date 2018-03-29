defmodule Aecore.Structures.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState
  alias Aecore.Structures.SpendTx
  alias Aeutil.Serialization
  alias Aeutil.Parser

  require Logger

  @typedoc "Name of the specified transaction module"
  @type tx_types :: SpendTx

  @typedoc "Structure of a transaction that may be added to be blockchain"
  @type payload :: SpendTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the main transaction wrapper"
  @type t :: %DataTx{
          type: tx_types(),
          payload: payload(),
          sender: binary(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @doc """
  Definition of Aecore DataTx structure

  ## Parameters
  - type: The type of transaction that may be added to the blockchain
  - payload: The strcuture of the specified transaction type
  - sender: The public address of the account originating the transaction
  - fee: The amount of tokens given to the miner
  - nonce: A random integer generated on initialisation of a transaction (must be unique!)
  """
  defstruct [:type, :payload, :sender, :fee, :nonce]
  use ExConstructor

  @spec init(tx_types(), payload(), binary(), integer(), integer()) :: DataTx.t()
  def init(type, payload, sender, fee, nonce) do
    %DataTx{type: type, payload: type.init(payload), sender: sender, fee: fee, nonce: nonce}
  end

  @doc """
  Checks whether the fee is above 0. If it is, it runs the transaction type
  validation checks. Otherwise we return error.
  """
  @spec is_valid?(DataTx.t()) :: boolean()
  def is_valid?(%DataTx{type: type, payload: payload, fee: fee}) do
    if fee > 0 do
      payload
      |> type.init()
      |> type.is_valid?()
    else
      Logger.error("Fee not enough")
      false
    end
  end

  @doc """
  Changes the chainstate (account state and tx_type_state) according
  to the given transaction requirements
  """
  @spec process_chainstate!(DataTx.t(), ChainState.chainstate()) :: ChainState.chainstate()
  def process_chainstate!(%DataTx{} = tx, chainstate) do
    accounts_state_tree = chainstate.accounts
    tx_type_state = Map.get(chainstate, tx.type, %{})

    {new_accounts_state_tree, new_tx_type_state} =
      tx.payload
      |> tx.type.init()
      |> tx.type.process_chainstate!(
        tx.sender,
        tx.fee,
        tx.nonce,
        accounts_state_tree,
        tx_type_state
      )

    new_chainstate =
      if Map.has_key?(chainstate, tx.type) do
        Map.put(chainstate, tx.type, new_tx_type_state)
      else
        chainstate
      end

    Map.put(new_chainstate, :accounts, new_accounts_state_tree)
  end

  @spec serialize(DataTx.t()) :: map()
  def serialize(%DataTx{} = tx) do
    tx
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, value}, new_tx ->
      Map.put(new_tx, Parser.to_string!(key), Serialization.serialize_value(value))
    end)
  end

  @spec deserialize(payload()) :: DataTx.t()
  def deserialize(%{} = tx) do
    data_tx = Serialization.deserialize_value(tx)
    init(data_tx.type, data_tx.payload, data_tx.sender, data_tx.fee, data_tx.nonce)
  end
end
