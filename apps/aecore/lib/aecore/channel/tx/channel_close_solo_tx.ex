defmodule Aecore.Channel.Tx.ChannelCloseSoloTx do
  @moduledoc """
  Module defining the ChannelCloseSolo transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelOffChainTx, ChannelStateTree}
  alias Aecore.Chain.Identifier
  alias Aecore.Poi.Poi
  alias Aeutil.Serialization

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCloseSolo Transaction"
  @type payload :: %{
          channel_id: binary(),
          offchain_tx: map() | atom(),
          poi: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelCloseSoloTx Transaction type"
  @type t :: %ChannelCloseSoloTx{
          channel_id: binary(),
          offchain_tx: ChannelOffChainTx.t() | :empty,
          poi: Poi.t()
        }

  @doc """
  Definition of the ChannelCloseSoloTx structure

  # Parameters
  - state - the (final) state with which the channel is going to be closed
  """
  defstruct [:channel_id, :offchain_tx, :poi]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCloseSoloTx.t()
  def init(%{channel_id: channel_id, offchain_tx: offchain_tx, poi: %Poi{} = poi} = _payload) do
    %ChannelCloseSoloTx{
      channel_id: channel_id,
      offchain_tx: offchain_tx,
      poi: poi
    }
  end

  @spec channel_id(ChannelCloseSoloTx.t()) :: binary()
  def channel_id(%ChannelCloseSoloTx{channel_id: channel_id}), do: channel_id

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCloseSoloTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelCloseSoloTx{offchain_tx: :empty}, %DataTx{senders: senders}) do
    if length(senders) != 1 do
      {:error, "#{__MODULE__}: Invalid senders size"}
    else
      :ok
    end
  end

  def validate(
        %ChannelCloseSoloTx{
          channel_id: internal_channel_id,
          offchain_tx: %ChannelOffChainTx{
            channel_id: offchain_tx_channel_id,
            state_hash: state_hash
          },
          poi: poi
        },
        %DataTx{senders: senders}
      ) do
    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      internal_channel_id !== offchain_tx_channel_id ->
        {:error, "#{__MODULE__}: Channel id mismatch"}

      Poi.calculate_root_hash(poi) !== state_hash ->
        {:error, "#{__MODULE__}: Invalid state_hash"}

      true ->
        :ok
    end
  end

  @doc """
  Performs a channel slash
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseSoloTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCloseSoloTx{
          channel_id: channel_id,
          offchain_tx: offchain_tx,
          poi: poi
        },
        _data_tx
      ) do
    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_slashing(channel, block_height, offchain_tx, poi)
      end)

    {:ok, {accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseSoloTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCloseSoloTx{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]}
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't solo close active channel. Use slash."}

      sender != channel.initiator_pubkey && sender != channel.responder_pubkey ->
        {:error, "#{__MODULE__}: Sender must be a party of the channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, offchain_tx, poi)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
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

  @spec encode_to_list(ChannelCloseSoloTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelCloseSoloTx{} = tx, %DataTx{senders: [sender]} = data_tx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(tx.channel_id, :channel),
      Identifier.encode_to_binary(sender),
      ChannelOffChainTx.encode_to_payload(tx.offchain_tx),
      Serialization.rlp_encode(tx.poi),
      :binary.encode_unsigned(data_tx.ttl),
      :binary.encode_unsigned(data_tx.fee),
      :binary.encode_unsigned(data_tx.nonce)
    ]
  end

  def decode_from_list(@version, [
        encoded_channel_id,
        encoded_sender,
        payload,
        rlp_encoded_poi,
        ttl,
        fee,
        nonce
      ]) do
    with {:ok, channel_id} <-
           Identifier.decode_from_binary_to_value(encoded_channel_id, :channel),
         {:ok, offchain_tx} <- ChannelOffChainTx.decode_from_payload(payload),
         {:ok, poi} <- Poi.rlp_decode(rlp_encoded_poi) do
      DataTx.init_binary(
        ChannelCloseSoloTx,
        %ChannelCloseSoloTx{
          channel_id: channel_id,
          offchain_tx: offchain_tx,
          poi: poi
        },
        [encoded_sender],
        :binary.decode_unsigned(fee),
        :binary.decode_unsigned(nonce),
        :binary.decode_unsigned(ttl)
      )
    else
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
