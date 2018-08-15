defmodule Aecore.Channel.Tx.ChannelCloseSoloTx do
  @moduledoc """
  Aecore structure of ChannelCloseSoloTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateOffChain, ChannelStateTree}
  alias Aecore.Chain.Identifier

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
  Definition of Aecore ChannelCloseSoloTx structure

  ## Parameters
  - state - the state to start close operation with
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCloseSoloTx.t()
  def init(%{state: state} = _payload) do
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
  Checks transactions internal contents validity
  """
  @spec validate(ChannelCloseSoloTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelCloseSoloTx{}, data_tx) do
    senders = DataTx.senders(data_tx)

    if length(senders) != 1 do
      {:error, "#{__MODULE__}: Invalid senders size"}
    else
      :ok
    end
  end

  @doc """
  Performs channel slash
  """
  @spec process_chainstate(
          Chainstate.account(),
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
  Checks whether all the data is valid according to the ChannelSoloCloseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          Chainstate.account(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseSoloTx.t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCloseSoloTx{state: state},
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
        ) :: Chainstate.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%ChannelCloseSoloTx{} = tx, %DataTx{} = data_tx) do
    [sender] = data_tx.senders
    [
      :binary.encode_unsigned(@version),
      tx.state.channel_id,
      Identifier.encode_to_binary(sender),
      ChannelStateOffChain.encode_to_list(tx.state),  #TODO payload + poi instead
      :binary.encode_unsigned(data_tx.ttl),
      :binary.encode_unsigned(data_tx.fee),
      :binary.encode_unsigned(data_tx.nonce)
    ]
  end

  def decode_from_list(@version, [
                         channel_id,
                         encoded_sender,
                         [state_ver_bin | state],  #TODO payload + poi instead
                         ttl,
                         fee,
                         nonce
                       ]) do
    state_ver = :binary.decode_unsigned(state_ver_bin)

    with{:ok, state} <- ChannelStateOffChain.decode_from_list(state_ver, state),
        {:ok, sender} <- Identifier.decode_from_binary(encoded_sender) do
      if channel_id != state.channel_id do
        {:error, "#{__MODULE__}: channel_id mismatch"}
      else
        payload = %ChannelCloseSoloTx{state: state}

        DataTx.init_binary(
          ChannelCloseSoloTx,
          payload,
          [sender],
          :binary.encode_unsigned(fee),
          :binary.encode_unsigned(nonce),
          :binary.encode_unsigned(ttl)
        )
      end
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
