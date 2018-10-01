defmodule Aecore.Channel.Tx.ChannelSlashTx do
  @moduledoc """
  Module defining the ChannelSlash transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.AccountStateTree
  alias Aecore.Channel.{ChannelStateOnChain, ChannelOffChainTx, ChannelStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Poi.Poi
  alias Aeutil.Serialization

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSlash Transaction"
  @type payload :: %{
          channel_id: binary(),
          offchain_tx: map(),
          poi: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSlash Transaction type"
  @type t :: %ChannelSlashTx{
          channel_id: binary(),
          offchain_tx: ChannelOffChainTx.t(),
          poi: Poi.t()
        }

  @doc """
  Definition of the ChannelSlashTx structure

  # Parameters
  - state - the state with which the channel is going to be slashed
  """
  defstruct [:channel_id, :offchain_tx, :poi]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi} = _payload) do
    %ChannelSlashTx{
      channel_id: channel_id,
      offchain_tx: offchain_tx,
      poi: poi
    }
  end

  @spec channel_id(ChannelSlashTx.t()) :: binary()
  def channel_id(%ChannelSlashTx{channel_id: channel_id}), do: channel_id

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSlashTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%ChannelSlashTx{offchain_tx: :empty}) do
    {:error, "#{__MODULE__}: Can't slash without an offchain tx"}
  end

  def validate(
        %ChannelSlashTx{
          channel_id: internal_channel_id,
          offchain_tx: %ChannelOffChainTx{
            channel_id: offchain_tx_channel_id,
            sequence: sequence,
            state_hash: state_hash
          },
          poi: poi
        },
        %DataTx{senders: senders}
      ) do
    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      sequence == 0 ->
        {:error, "#{__MODULE__}: Can't slash with zero state"}

      internal_channel_id !== offchain_tx_channel_id ->
        {:error, "#{__MODULE__}: Channel id mismatch"}

      Poi.calculate_root_hash(poi) !== state_hash ->
        {:error, "#{__MODULE__}: Invalid state_hash"}

      true ->
        :ok
    end
  end

  @doc """
  Slashes the channel
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelSlashTx{
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
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelSlashTx{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi},
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]}
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't slash active channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, offchain_tx, poi)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSlashTx.t(),
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

  @spec encode_to_list(ChannelSlashTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelSlashTx{} = tx, %DataTx{} = datatx) do
    [sender] = datatx.senders

    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(tx.channel_id, :channel),
      Identifier.encode_to_binary(sender),
      ChannelOffChainTx.encode_to_payload(tx.offchain_tx),
      Serialization.rlp_encode(tx.poi),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.nonce)
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
        ChannelSlashTx,
        %ChannelSlashTx{
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
