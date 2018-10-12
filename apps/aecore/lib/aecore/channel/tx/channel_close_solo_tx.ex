defmodule Aecore.Channel.Tx.ChannelCloseSoloTx do
  @moduledoc """
  Module defining the ChannelCloseSolo transaction
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateOffChain, ChannelStateTree}

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCloseSolo Transaction"
  @type payload :: %{
          state: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelCloseSoloTx Transaction type"
  @type t :: %ChannelCloseSoloTx{
          state: ChannelStateOffChain.t()
        }

  @doc """
  Definition of the ChannelCloseSoloTx structure

  # Parameters
  - state - the (final) state with which the channel is going to be closed
  """
  defstruct [:state]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCloseSoloTx.t()
  def init(%{state: state}) do
    %ChannelCloseSoloTx{state: ChannelStateOffChain.init(state)}
  end

  @spec create(ChannelStateOffChain.t()) :: ChannelCloseSoloTx.t()
  def create(state) do
    %ChannelCloseSoloTx{state: state}
  end

  @spec sequence(ChannelCloseSoloTx.t()) :: non_neg_integer()
  def sequence(%ChannelCloseSoloTx{state: %ChannelStateOffChain{sequence: sequence}}),
    do: sequence

  @spec channel_id(ChannelCloseSoloTx.t()) :: binary()
  def channel_id(%ChannelCloseSoloTx{state: %ChannelStateOffChain{channel_id: id}}), do: id

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCloseSoloTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(%ChannelCloseSoloTx{}, %DataTx{} = data_tx) do
    senders = DataTx.senders(data_tx)

    if length(senders) != 1 do
      {:error, "#{__MODULE__}: Invalid senders size"}
    else
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
          state:
            %ChannelStateOffChain{
              channel_id: channel_id
            } = state
        },
        _data_tx
      ) do
    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_slashing(channel, block_height, state)
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
        %ChannelCloseSoloTx{state: state},
        %DataTx{fee: fee} = data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    channel = ChannelStateTree.get(channels, state.channel_id)

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
        ChannelStateOnChain.validate_slashing(channel, state)
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

  @spec encode_to_list(ChannelCloseSoloTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelCloseSoloTx{state: state}, %DataTx{
        senders: senders,
        nonce: nonce,
        fee: fee,
        ttl: ttl
      }) do
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_list_to_binary(senders),
      :binary.encode_unsigned(nonce),
      ChannelStateOffChain.encode_to_list(state),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [encoded_senders, nonce, [state_ver_bin | state], fee, ttl]) do
    state_ver = :binary.decode_unsigned(state_ver_bin)

    case ChannelStateOffChain.decode_from_list(state_ver, state) do
      {:ok, state} ->
        payload = %ChannelCloseSoloTx{state: state}

        DataTx.init_binary(
          ChannelCloseSoloTx,
          payload,
          encoded_senders,
          :binary.encode_unsigned(fee),
          :binary.encode_unsigned(nonce),
          :binary.encode_unsigned(ttl)
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
