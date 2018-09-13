defmodule Aecore.Channel.Tx.ChannelSettleTx do
  @moduledoc """
  Module defining the ChannelSettle transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelSettleTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree}
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSettle Transaction"
  @type payload :: %{
          channel_id: binary()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSettle Transaction type"
  @type t :: %ChannelSettleTx{
          channel_id: Identifier.t()
        }

  @doc """
  Definition of the ChannelSettleTx structure

  # Parameters
  - channel_id: channel id
  """
  defstruct [:channel_id]
  use ExConstructor

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCreateTx.t()
  def init(%{channel_id: channel_id} = _payload) do
    %ChannelSettleTx{channel_id: Identifier.create_identity(channel_id, :channel)}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelSettleTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%ChannelSettleTx{}, data_tx) do
    senders = DataTx.senders(data_tx)

    if length(senders) != 1 do
      {:error, "#{__MODULE__}: Invalid from_accs size"}
    else
      :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and closes the channel (drops the channel object)
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelSettleTx{channel_id: channel_id},
        _data_tx
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    new_accounts =
      accounts
      |> AccountStateTree.update(channel.initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, channel.initiator_amount)
      end)
      |> AccountStateTree.update(channel.responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, channel.responder_amount)
      end)

    new_channels = ChannelStateTree.delete(channels, channel_id)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        block_height,
        %ChannelSettleTx{channel_id: channel_id},
        data_tx
      ) do
    fee = DataTx.fee(data_tx)
    sender = DataTx.main_sender(data_tx)

    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance < fee ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.settled?(channel, block_height) ->
        {:error, "#{__MODULE__}: Channel isn't settled"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSettleTx.t(),
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

  @spec encode_to_list(ChannelSettleTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelSettleTx{} = tx, %DataTx{} = datatx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(tx.channel_id),
      Identifier.encode_list_to_binary(datatx.senders),
      :binary.encode_unsigned(datatx.nonce),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.ttl)
    ]
  end

  defp decode_channel_identifier_to_binary(encoded_identifier) do
  {:ok, %Identifier{type: :channel, value: value}} = Identifier.decode_from_binary(encoded_identifier)
    value
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [channel_id, encoded_senders, nonce, fee, ttl]) do
    payload = %ChannelSettleTx{channel_id: decode_channel_identifier_to_binary(channel_id)}

    DataTx.init_binary(
      ChannelSettleTx,
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
