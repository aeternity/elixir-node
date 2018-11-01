defmodule Aecore.Channel.Tx.ChannelCloseSoloTx do
  @moduledoc """
  Module defining the ChannelCloseSolo transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Identifier, Chainstate}
  alias Aecore.Channel.{ChannelStateOnChain, ChannelOffChainTx, ChannelStateTree}
  alias Aecore.Channel.Tx.{ChannelCloseSoloTx, ChannelCreateTx}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Poi.Poi
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCloseSolo Transaction"
  @type payload :: %{
          channel_id: binary(),
          offchain_tx: map() | :empty,
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

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

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
      !Identifier.valid?(senders, :account) ->
        {:error, "#{__MODULE__}: Invalid senders identifier: #{inspect(senders)}"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size #{length(senders)}"}

      internal_channel_id !== offchain_tx_channel_id ->
        {:error,
         "#{__MODULE__}: OffChainTx channel id mismatch, expected #{inspect(internal_channel_id)}, got #{
           inspect(offchain_tx_channel_id)
         }"}

      Poi.calculate_root_hash(poi) !== state_hash ->
        {:error,
         "#{__MODULE__}: Invalid Poi root_hash, expcted #{inspect(state_hash)}, got #{
           inspect(Poi.calculate_root_hash(poi))
         }"}

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
          DataTx.t(),
          Transaction.context()
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
        _data_tx,
        _context
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
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCloseSoloTx{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi},
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

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelCloseSoloTx.t(), DataTx.t()) :: list() | {:error, String.t()}
  def encode_to_list(%ChannelCloseSoloTx{} = tx, %DataTx{senders: [sender]} = data_tx) do
    offchain_tx_encoded =
      if tx.offchain_tx != :empty do
        ChannelOffChainTx.rlp_encode(tx.offchain_tx)
      else
        <<>>
      end

    case Serialization.rlp_encode(tx.poi) do
      serialized_poi when is_binary(serialized_poi) ->
        [
          :binary.encode_unsigned(@version),
          Identifier.create_encoded_to_binary(tx.channel_id, :channel),
          Identifier.encode_to_binary(sender),
          offchain_tx_encoded,
          serialized_poi,
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
        rlp_encoded_poi,
        ttl,
        fee,
        nonce
      ]) do
    with {:ok, channel_id} <-
           Identifier.decode_from_binary_to_value(encoded_channel_id, :channel),
         {:ok, offchain_tx} <- decode_payload(payload),
         {:ok, poi} <- Poi.rlp_decode(rlp_encoded_poi) do
      DataTx.init_binary(
        ChannelCloseSoloTx,
        %{
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

  defp decode_payload(<<>>) do
    {:ok, :empty}
  end

  defp decode_payload(payload) do
    ChannelOffChainTx.rlp_decode_signed(payload)
  end
end
