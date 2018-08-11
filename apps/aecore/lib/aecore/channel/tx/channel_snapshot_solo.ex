defmodule Aecore.Channel.Tx.ChannelSnapshotSoloTx do
  @moduledoc """
  Aecore structure of ChannelSnapshotSoloTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelSnapshotSoloTx
  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStateTree
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx
  alias Aecore.Chain.Identifier

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSnapshotSolo Transaction"
  @type payload :: %{
          channel_id: binary(),
          state: map(),
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSnapshotSolo Transaction type"
  @type t :: %ChannelSnapshotSoloTx{
          state: ChannelStateOffChain.t()
        }

  @doc """
  Definition of Aecore ChannelSnapshotSoloTx structure

  ## Parameters
  - state - the snapshoted state
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{state: state} = _payload) do
    %ChannelSnapshotSoloTx{state: ChannelStateOffChain.init(state)}
  end

  @doc """
  Creates the transaction from a channel offchain state
  """
  @spec create(ChannelStateOffChain.t()) :: ChannelSnapshotSoloTx.t()
  def create(state) do
    %ChannelSnapshotSoloTx{state: state}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSnapshotSoloTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSnapshotSoloTx{state: %ChannelStateOffChain{sequence: sequence}}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      sequence == 0 ->
        {:error, "#{__MODULE__}: Can't slash with zero state"}

      true ->
        :ok
    end
  end

  @doc """
  Snapshots a channel.
  """
  @spec process_chainstate(
          Chainstate.account(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSnapshotSoloTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        _block_height,
        %ChannelSnapshotSoloTx{
          state:
            %ChannelStateOffChain{
              channel_id: channel_id
            } = state
        },
        _data_tx
      ) do
    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_snapshot(channel, state)
      end)

    {:ok, {accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the ChannelSnapshotTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          Chainstate.account(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSnapshotSoloTx.t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelSnapshotSoloTx{state: state},
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    channel = ChannelStateTree.get(channels, state.channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative sender balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't submit snapshot when channel is closing (use slash)"}

      true ->
        ChannelStateOnChain.validate_snapshot(channel, state)
   end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSnapshotSoloTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%ChannelSnapshotSoloTx{} = tx, %DataTx{} = datatx) do
    [
      @version,
      Identifier.encode_list_to_binary(datatx.senders),
      datatx.nonce,
      ChannelStateOffChain.encode_to_list(tx.state),
      datatx.fee,
      datatx.ttl
    ]
  end

  def decode_from_list(@version, [encoded_senders, nonce, [state_ver_bin | state], fee, ttl]) do
    state_ver = Serialization.transform_item(state_ver_bin, :int)

    case ChannelStateOffChain.decode_from_list(state_ver, state) do
      {:ok, state} ->
        payload = %ChannelSnapshotSoloTx{state: state}

        DataTx.init_binary(
          ChannelSnapshotSoloTx,
          payload,
          encoded_senders,
          fee,
          nonce,
          ttl
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
