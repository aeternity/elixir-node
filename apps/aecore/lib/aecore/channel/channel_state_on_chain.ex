defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  State Channel OnChain structure
  """

  require Logger

  alias Aecore.Keys
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelOffchainTx
  alias Aecore.Poi.Poi
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash
  alias Aeutil.Serialization

  @version 1

  @type t :: %ChannelStateOnChain{
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          initiator_amount: integer(),
          responder_amount: integer(),
          lock_period: non_neg_integer(),
          slash_close: integer(),
          slash_sequence: integer(),
          state_hash: binary(),
          channel_reserve: non_neg_integer()
        }

  @type id :: binary()

  @doc """
  Definition of State Channel OnChain structure

  ## Parameters
  - initiator_pubkey
  - responder_pubkey
  - initiator_amount - amount deposited by initiator or from slashing
  - responder_amount - amount deposited by responder or from slashing
  - lock_period - time before slashing is settled
  - slash_close - when != 0: block height when slashing is settled
  - slash_sequence - when != 0: sequence or slashing
  - state_hash - root hash of last known offchain chainstate
  - channel_reserve - minimal ammount of tokens held by the initiator or responder
  """
  defstruct [
    :initiator_pubkey,
    :responder_pubkey,
    :initiator_amount,
    :responder_amount,
    :lock_period,
    :slash_close,
    :slash_sequence,
    :state_hash,
    :channel_reserve
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(Keys.pubkey(), Keys.pubkey(), integer(), integer(), non_neg_integer(), non_neg_integer(), binary()) ::
          ChannelStateOnChain.t()
  def create(initiator_pubkey, responder_pubkey, initiator_amount, responder_amount, lock_period, channel_reserve, state_hash) do
    %ChannelStateOnChain{
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      lock_period: lock_period,
      slash_close: 0,
      slash_sequence: 0,
      state_hash: state_hash,
      channel_reserve: channel_reserve
    }
  end

  @doc """
  Generates channel id from ChannelCreateTx.
  """
  @spec id(DataTx.t()) :: id()
  def id(data_tx) do
    nonce = DataTx.nonce(data_tx)
    [initiator_pubkey, responder_pubkey] = DataTx.senders(data_tx)
    id(initiator_pubkey, responder_pubkey, nonce)
  end

  @doc """
  Generates channel id from detail of ChannelCreateTx.
  """
  @spec id(Keys.pubkey(), Keys.pubkey(), non_neg_integer()) :: id()
  def id(initiator_pubkey, responder_pubkey, nonce) do
    binary_data = initiator_pubkey <> <<nonce::size(64)>> <> responder_pubkey

    Hash.hash_blake2b(binary_data)
  end

  @spec amounts(ChannelStateOnChain.t()) :: {non_neg_integer(), non_neg_integer()}
  def amounts(%ChannelStateOnChain{
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    {initiator_amount, responder_amount}
  end

  @spec pubkeys(ChannelStateOnChain.t()) :: {Keys.pubkey(), Keys.pubkey()}
  def pubkeys(%ChannelStateOnChain{
        initiator_pubkey: initiator_pubkey,
        responder_pubkey: responder_pubkey
      }) do
    {initiator_pubkey, responder_pubkey}
  end

  @doc """
  Returns true if channel wasn't slashed. (Closed channels should be removed from Channels state tree)
  """
  @spec active?(ChannelStateOnChain.t()) :: boolean()
  def active?(%ChannelStateOnChain{slash_close: 0}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  @doc """
  Returns true if Channel can be settled. (If Channel was slashed and current block height exceeds locktime)
  """
  @spec settled?(ChannelStateOnChain.t(), non_neg_integer()) :: boolean()
  def settled?(%ChannelStateOnChain{slash_close: slash_close} = channel, block_height) do
    block_height >= slash_close && !active?(channel)
  end

  @doc """
  Validates SlashTx and SoloCloseTx payload and poi.
  """
  @spec validate_slashing(ChannelStateOnChain.t(), ChannelOffChainTx.t() | :empty, Poi.t()) ::
          :ok | {:error, binary()}
  def validate_slashing(
        %ChannelStateOnChain{} = channel,
        :empty,
        %Poi{} = poi
      ) do
    cond do
      #No payload is only allowed for SoloCloseTx
      channel.slash_sequence != 0 ->
        {:error, "#{__MODULE__}: Channel already slashed"}

      channel.state_hash !== Poi.calculate_root_hash(poi) ->
        {:error, "#{__MODULE__}: Invalid state hash"}

      true ->
        case Poi.get_account_balance_from_poi(poi, channel.initiator_pubkey) do
          {:ok, poi_initiator_amount} ->
            case Poi.get_account_balance_from_poi(poi, channel.responder_pubkey) do
              {:ok, poi_respoder_amount} ->
                if poi_initiator_amount + poi_respoder_amount !== channel.initiator_amount + channel.responder_amount do
                  #The total amount MUST never change
                  {:error, "#{__MODULE__}: Invalid total amount"}
                else
                  :ok
                end
              {:error, _} ->
                {:error, "#{__MODULE__}: Poi does not contain responder's offchain account."}
            end
          {:error, _} ->
            {:error, "#{__MODULE__}: Poi does not contain initiator's offchain account."}
        end
    end
  end

  def validate_slashing(
        %ChannelStateOnChain{} = channel,
        %ChannelOffchainTx{} = offchain_tx,
        %Poi{} = poi) do
    cond do
      channel.slash_sequence >= offchain_tx.sequence ->
        {:error, "#{__MODULE__}: Offchain state is too old"}

      offchain_tx.state_hash !== Poi.calculate_root_hash(poi) ->
        {:error, "#{__MODULE__}: Invalid state hash"}

      true ->
        case Poi.get_account_balance_from_poi(poi, channel.initiator_pubkey) do
          {:ok, poi_initiator_amount} ->
            case Poi.get_account_balance_from_poi(poi, channel.responder_pubkey) do
              {:ok, poi_respoder_amount} ->
                if poi_initiator_amount + poi_respoder_amount !== channel.initiator_amount + channel.responder_amount do
                  #The total amount MUST never change
                  {:error, "#{__MODULE__}: Invalid total amount"}
                else
                  ChannelOffchainTx.validate(offchain_tx, pubkeys(channel))
                end
              {:error, _} ->
                {:error, "#{__MODULE__}: Poi does not contain responder's offchain account."}
            end
          {:error, _} ->
            {:error, "#{__MODULE__}: Poi does not contain initiator's offchain account."}
        end
    end
  end

  @doc """
  Executes slashing on channel. Slashing should be validated before with validate_slashing.
  """
  @spec apply_slashing(ChannelStateOnChain.t(), non_neg_integer(), ChannelOffchainTx.t() | :empty, Poi.t()) ::
          ChannelStateOnChain.t()
  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, :empty, %Poi{} = poi) do
    {:ok, initiator_amount} = Poi.get_account_balance_from_poi(poi, channel.initiator_pubkey)
    {:ok, responder_amount} = Poi.get_account_balance_from_poi(poi, channel.responder_pubkey)
    %ChannelStateOnChain{
      channel
      |
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        slash_close: block_height + channel.lock_period,
        slash_sequence: 0
    }
  end

  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, %ChannelOffchainTx{} = offchain_tx, %Poi{} = poi) do
    {:ok, initiator_amount} = Poi.get_account_balance_from_poi(poi, channel.initiator_pubkey)
    {:ok, responder_amount} = Poi.get_account_balance_from_poi(poi, channel.responder_pubkey)
    %ChannelStateOnChain{
      channel
      | slash_close: block_height + channel.lock_period,
        slash_sequence: offchain_tx.sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
    }
  end

  @spec encode_to_list(ChannelStateOnChain.t()) :: list() | {:error, String.t()}
  def encode_to_list(%ChannelStateOnChain{} = channel) do
    [
      :binary.encode_unsigned(@version),
      channel.initiator_pubkey,
      channel.responder_pubkey,
      :binary.encode_unsigned(channel.initiator_amount + channel.responder_amount),
      :binary.encode_unsigned(channel.initiator_amount),
      :binary.encode_unsigned(channel.channel_reserve),
      channel.state_hash,
      :binary.encode_unsigned(channel.slash_sequence),
      :binary.encode_unsigned(channel.lock_period),
      :binary.encode_unsigned(channel.slash_close)
    ]
  end

  @spec decode_from_list(integer(), list()) ::
          {:ok, ChannelStateOnChain.t()} | {:error, String.t()}
  def decode_from_list(@version, [
        initiator_pubkey,
        responder_pubkey,
        encoded_total_amount,
        encoded_initiator_amount,
        channel_reserve,
        state_hash,
        slash_sequence,
        lock_period,
        slash_close
      ]) do
    initiator_amount = :binary.decode_unsigned(encoded_initiator_amount)
    total_amount = :binary.decode_unsigned(encoded_total_amount)
    {:ok,
     %ChannelStateOnChain{
       initiator_pubkey: initiator_pubkey,
       responder_pubkey: responder_pubkey,
       initiator_amount: initiator_amount,
       responder_amount: total_amount - initiator_amount,
       lock_period: :binary.decode_unsigned(lock_period),
       slash_close: :binary.decode_unsigned(slash_close),
       slash_sequence: :binary.decode_unsigned(slash_sequence),
       state_hash: state_hash,
       channel_reserve: :binary.decode_unsigned(channel_reserve)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
