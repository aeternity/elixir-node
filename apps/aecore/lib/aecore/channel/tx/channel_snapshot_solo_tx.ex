defmodule Aecore.Channel.Tx.ChannelSnapshotSoloTx do
  @moduledoc """
  Module defining the ChannelSnapshotSoloTx transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Channel.Tx.ChannelSnapshotSoloTx
  alias Aecore.Channel.{ChannelStateOnChain, ChannelOffChainTx, ChannelStateTree}
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Chain.{Identifier, Chainstate}

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSnapshotSolo Transaction"
  @type payload :: %{
          channel_id: binary(),
          offchain_tx: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSnapshotSolo Transaction type"
  @type t :: %ChannelSnapshotSoloTx{
          channel_id: binary(),
          offchain_tx: ChannelOffChainTx.t()
        }

  @doc """
  Definition of Aecore ChannelSnapshotSoloTx structure

  ## Parameters
  - channel_id - the id of the channel for which the transaction is designated
  - offchain_tx - off chain transaction mutually signed by both parties of the channel
  """
  defstruct [:channel_id, :offchain_tx]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  @spec init(payload()) :: ChannelSnapshotSoloTx.t()
  def init(%{channel_id: channel_id, offchain_tx: offchain_tx} = _payload) do
    %ChannelSnapshotSoloTx{channel_id: channel_id, offchain_tx: offchain_tx}
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelSnapshotSoloTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %ChannelSnapshotSoloTx{
          channel_id: internal_channel_id,
          offchain_tx: %ChannelOffChainTx{
            channel_id: offchain_tx_channel_id,
            sequence: sequence,
            state_hash: state_hash
          }
        },
        %DataTx{senders: senders}
      ) do
    cond do
      !Identifier.valid?(senders, :account) ->
        {:error, "#{__MODULE__}: Invalid senders identifier: #{inspect(senders)}"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size #{length(senders)}"}

      sequence <= 0 ->
        {:error, "#{__MODULE__}: Sequence has to be positive"}

      internal_channel_id !== offchain_tx_channel_id ->
        {:error,
         "#{__MODULE__}: OffChainTx channel id mismatch, expected #{inspect(internal_channel_id)}, got #{
           inspect(offchain_tx_channel_id)
         }"}

      byte_size(state_hash) != 32 ->
        {:error, "#{__MODULE__}: Invalid state hash size byte_size(state_hash)"}

      true ->
        :ok
    end
  end

  @doc """
  Snapshots a channel.
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSnapshotSoloTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        _block_height,
        %ChannelSnapshotSoloTx{
          channel_id: channel_id,
          offchain_tx: offchain_tx
        },
        _data_tx,
        _context
      ) do
    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_snapshot(channel, offchain_tx)
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
          ChannelSnapshotSoloTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelSnapshotSoloTx{channel_id: channel_id, offchain_tx: offchain_tx},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]},
        _context
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't submit snapshot when channel is closing (use slash)"}

      !ChannelStateOnChain.is_peer_or_delegate?(channel, sender) ->
        {:error,
         "#{__MODULE__}: Sender #{sender} is not a peer or delegate of the channel, peers are: #{
           channel.initiator_pubkey
         } and #{channel.responder_pubkey}, delegates are: #{channel.delegates} "}

      true ->
        ChannelStateOnChain.validate_snapshot(channel, offchain_tx)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSnapshotSoloTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelSnapshotSoloTx.t(), DataTx.t()) :: list() | {:error, String.t()}
  def encode_to_list(%ChannelSnapshotSoloTx{} = tx, %DataTx{senders: [sender]} = data_tx) do
    case ChannelOffChainTx.rlp_encode(tx.offchain_tx) do
      offchain_tx_encoded when is_binary(offchain_tx_encoded) ->
        [
          :binary.encode_unsigned(@version),
          Identifier.create_encoded_to_binary(tx.channel_id, :channel),
          Identifier.encode_to_binary(sender),
          offchain_tx_encoded,
          :binary.encode_unsigned(data_tx.ttl),
          :binary.encode_unsigned(data_tx.fee),
          :binary.encode_unsigned(data_tx.nonce)
        ]

      {:error, _} = err ->
        err
    end
  end

  def decode_from_list(@version, [
        encoded_channel_id,
        encoded_sender,
        payload,
        ttl,
        fee,
        nonce
      ]) do
    with {:ok, channel_id} <-
           Identifier.decode_from_binary_to_value(encoded_channel_id, :channel),
         {:ok, offchain_tx} <- ChannelOffChainTx.rlp_decode_signed(payload) do
      DataTx.init_binary(
        ChannelSnapshotSoloTx,
        %{
          channel_id: channel_id,
          offchain_tx: offchain_tx
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
