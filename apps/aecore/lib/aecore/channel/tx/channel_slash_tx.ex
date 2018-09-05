defmodule Aecore.Channel.Tx.ChannelSlashTx do
  @moduledoc """
  Aecore structure of ChannelSlashTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelOffchainTx, ChannelStateTree}
  alias Aecore.Chain.Identifier
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
          channel_id: Identifier.t(),
          offchain_tx: ChannelOffchainTx.t(),
          poi: Poi.t()
        }

  @doc """
  Definition of Aecore ChannelSlashTx structure

  ## Parameters
  - state - the state to slash with
  """
  defstruct [:channel_id, :offchain_tx, :poi]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi} = _payload) do
    %ChannelSlashTx{
      channel_id: Identifier.create_identity(channel_id, :channel),
      offchain_tx: offchain_tx,
      poi: poi
    }
  end

  @spec channel_id(ChannelSlashTx.t()) :: binary()
  def channel_id(%ChannelSlashTx{channel_id: channel_id}), do: channel_id

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSlashTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSlashTx{offchain_tx: :empty}) do
    {:error, "#{__MODULE__}: Can't slash without an offchain tx"}
  end

  def validate(%ChannelSlashTx{channel_id: internal_channel_id, offchain_tx: %ChannelOffchainTx{channel_id: offchain_tx_channel_id, sequence: sequence, state_hash: state_hash}, poi: poi}, data_tx) do
    senders = DataTx.senders(data_tx)

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
        %ChannelSlashTx{channel_id: channel_id, offchain_tx: offchain_tx, poi: poi},
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

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
        ) :: Chainstate.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def encode_to_list(%ChannelSlashTx{} = tx, %DataTx{} = datatx) do
    main_sender = Identifier.create_identity(DataTx.main_sender(datatx), :account)
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(tx.channel_id),
      Identifier.encode_to_binary(main_sender),
      ChannelOffchainTx.encode_to_payload(tx.offchain_tx),
      Serialization.rlp_encode(tx.poi),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.nonce)
    ]
  end

  defp decode_channel_identifier_to_binary(encoded_identifier) do
  {:ok, %Identifier{type: :channel, value: value}} = Identifier.decode_from_binary(encoded_identifier)
    value
  end

  def decode_from_list(@version, [channel_id, encoded_sender, payload, rlp_encoded_poi, ttl, fee, nonce]) do
    case ChannelOffchainTx.decode_from_payload(payload) do
      {:ok, offchain_tx} ->
        case Serialization.rlp_decode_only(rlp_encoded_poi, Poi) do
          {:ok, poi} ->
            DataTx.init_binary(
              ChannelSlashTx,
              %{
                channel_id: decode_channel_identifier_to_binary(channel_id),
                offchain_tx: offchain_tx,
                poi: poi
              },
              [encoded_sender],
              :binary.decode_unsigned(fee),
              :binary.decode_unsigned(nonce),
              :binary.decode_unsigned(ttl)
            )
          {:error, _} = err ->
            err
        end
      {:error, _} = err ->
        err
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
