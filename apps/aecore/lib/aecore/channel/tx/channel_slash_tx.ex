defmodule Aecore.Channel.Tx.ChannelSlashTx do
  @moduledoc """
  Aecore structure of ChannelSlashTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateOffChain, ChannelStateTree}
  alias Aeutil.Serialization

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSlash Transaction"
  @type payload :: %{
          state: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSlash Transaction type"
  @type t :: %ChannelSlashTx{
          state: ChannelStateOffChain.t()
        }

  @doc """
  Definition of Aecore ChannelSlashTx structure

  ## Parameters
  - state - the state to slash with
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{state: state} = _payload) do
    %ChannelSlashTx{state: ChannelStateOffChain.init(state)}
  end

  @spec create(ChannelStateOffChain.t()) :: ChannelSlashTx.t()
  def create(state) do
    %ChannelSlashTx{state: state}
  end

  @spec sequence(ChannelSlashTx.t()) :: non_neg_integer()
  def sequence(%ChannelSlashTx{state: %ChannelStateOffChain{sequence: sequence}}), do: sequence

  @spec channel_id(ChannelSlashTx.t()) :: binary()
  def channel_id(%ChannelSlashTx{state: %ChannelStateOffChain{channel_id: id}}), do: id

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSlashTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSlashTx{state: %ChannelStateOffChain{sequence: sequence}}, data_tx) do
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
  Slashes channel.
  """
  @spec process_chainstate(
          Chainstate.account(),
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
  Checks whether all the data is valid according to the ChannelSlashTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          Chainstate.account(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelSlashTx.t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelSlashTx{state: state},
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

      ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't slash active channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, state)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelSlashTx.t(),
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

  def encode_to_list(%ChannelSlashTx{} = tx, %DataTx{} = datatx) do
    [
      @version,
      datatx.senders,
      datatx.nonce,
      ChannelStateOffChain.encode_to_list(tx.state),
      datatx.fee,
      datatx.ttl
    ]
  end

  def decode_from_list(@version, [senders, nonce, [state_ver_bin | state], fee, ttl]) do
    state_ver = Serialization.transform_item(state_ver_bin, :int)

    case ChannelStateOffChain.decode_from_list(state_ver, state) do
      {:ok, state} ->
        payload = %ChannelSlashTx{state: state}

        {:ok,
         DataTx.init(
           ChannelSlashTx,
           payload,
           senders,
           Serialization.transform_item(fee, :int),
           Serialization.transform_item(nonce, :int),
           Serialization.transform_item(ttl, :int)
         )}

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
