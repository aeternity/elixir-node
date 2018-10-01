defmodule Aecore.Account.Tx.SpendTx do
  @moduledoc """
  Module defining the Spend transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Chain.{Identifier, Chainstate}
  alias Aecore.Keys
  alias Aecore.Tx.{DataTx, SignedTx}

  require Logger

  @version 1

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          receiver: Keys.pubkey() | Identifier.t(),
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
          receiver: Keys.pubkey() | Identifier.t(),
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
  @spec validate(SpendTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %SpendTx{receiver: receiver, amount: amount, version: version, payload: payload},
        %DataTx{senders: senders}
      ) do
    cond do
      amount < 0 ->
        {:error, "#{__MODULE__}: The amount cannot be a negative number"}

      version != get_tx_version() ->
        {:error, "#{__MODULE__}: Invalid version"}

      !Keys.key_size_valid?(receiver) ->
        {:error, "#{__MODULE__}: Wrong receiver key size"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      !is_binary(payload) ->
        {:error,
         "#{__MODULE__}: Invalid payload type , expected binary , got: #{inspect(payload)} "}

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
  def process_chainstate(
        accounts,
        %{},
        block_height,
        %SpendTx{amount: amount, receiver: %Identifier{value: receiver}},
        %DataTx{senders: [%Identifier{value: sender}]}
      ) do
    new_accounts =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, amount * -1)
      end)
      |> AccountStateTree.update(receiver, fn acc ->
        Account.apply_transfer!(acc, block_height, amount)
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
  def preprocess_check(accounts, %{}, _block_height, %SpendTx{amount: amount}, %DataTx{
        fee: fee,
        senders: [%Identifier{value: sender}]
      }) do
    %Account{balance: balance} = AccountStateTree.get(accounts, sender)

    if balance - (fee + amount) < 0 do
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
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(%SignedTx{data: %DataTx{fee: fee}}) do
    fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  @spec get_tx_version() :: version()
  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]

  @spec encode_to_list(SpendTx.t(), DataTx.t()) :: list()
  def encode_to_list(%SpendTx{receiver: receiver, amount: amount, payload: payload}, %DataTx{
        senders: [sender],
        fee: fee,
        ttl: ttl,
        nonce: nonce
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      Identifier.encode_to_binary(receiver),
      :binary.encode_unsigned(amount),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl),
      :binary.encode_unsigned(nonce),
      payload
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
    case Identifier.decode_from_binary(encoded_receiver) do
      {:ok, receiver} ->
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
