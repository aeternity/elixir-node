defmodule Aecore.Account.Tx.SpendTx do
  @moduledoc """
  Module defining the Spend transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          receiver: Keys.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer(),
          payload: binary()
        }

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Version of SpendTx"
  @type version :: non_neg_integer()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: map()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %SpendTx{
          receiver: Keys.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer(),
          payload: binary()
        }

  @doc """
  Definition of the SpendTx structure

  # Parameters
  - receiver: the account to receive the transaction amount
  - amount: the amount of coins to be sent
  - version: specifies the version of the transaction
  - payload: any binary data (a message, a picture etc.)
  """
  defstruct [:receiver, :amount, :version, :payload]

  # Callbacks

  @spec get_chain_state_name() :: atom()
  def get_chain_state_name, do: :accounts

  @spec init(payload()) :: SpendTx.t()
  def init(%{
        receiver: %Identifier{} = identified_receiver,
        amount: amount,
        version: version,
        payload: payload
      }) do
    %SpendTx{receiver: identified_receiver, amount: amount, payload: payload, version: version}
  end

  def init(%{receiver: receiver, amount: amount, version: version, payload: payload}) do
    identified_receiver = Identifier.create_identity(receiver, :account)

    %SpendTx{receiver: identified_receiver, amount: amount, payload: payload, version: version}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(SpendTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%SpendTx{receiver: receiver} = tx, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      tx.amount < 0 ->
        {:error, "#{__MODULE__}: The amount cannot be a negative number"}

      tx.version != get_tx_version() ->
        {:error, "#{__MODULE__}: Invalid version"}

      !Keys.key_size_valid?(receiver) ->
        {:error, "#{__MODULE__}: Wrong receiver key size"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      !is_binary(tx.payload) ->
        {:error,
         "#{__MODULE__}: Invalid payload type , expected binary , got: #{inspect(tx.payload)} "}

      true ->
        :ok
    end
  end

  @doc """
  Deducts the transaction amount from the sender account state and adds it to the receiver
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          SpendTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(accounts, %{}, block_height, %SpendTx{} = tx, data_tx) do
    sender = DataTx.main_sender(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.amount * -1)
      end)
      |> AccountStateTree.update(tx.receiver.value, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.amount)
      end)

    {:ok, {new_accounts, %{}}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          SpendTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(accounts, %{}, _block_height, tx, data_tx) do
    sender_state = AccountStateTree.get(accounts, DataTx.main_sender(data_tx))

    if sender_state.balance - (DataTx.fee(data_tx) + tx.amount) < 0 do
      {:error, "#{__MODULE__}: Negative balance"}
    else
      :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          SpendTx.t(),
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

  @spec get_tx_version() :: version()
  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]

  @spec encode_to_list(SpendTx.t(), DataTx.t()) :: list() | {:error, reason()}
  def encode_to_list(%SpendTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      Identifier.encode_to_binary(tx.receiver),
      :binary.encode_unsigned(tx.amount),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.nonce),
      tx.payload
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        encoded_receiver,
        amount,
        fee,
        ttl,
        nonce,
        payload
      ]) do
    with {:ok, receiver} <- Identifier.decode_from_binary(encoded_receiver) do
      DataTx.init_binary(
        SpendTx,
        %{
          receiver: receiver,
          amount: :binary.decode_unsigned(amount),
          version: @version,
          payload: payload
        },
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
