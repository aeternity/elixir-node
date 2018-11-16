defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  State Channel OnChain structure
  """

  require Logger

  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelOffChainTx
  alias Aecore.Poi.Poi
  alias Aecore.Tx.DataTx
  alias Aeutil.Hash
  alias Aecore.Keys
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier
  alias Aecore.Tx.DataTx

  @version 1

  # This is the channel structure introduced in epoch 0.22 but is serialized to the 0.16 format
  @type t :: %ChannelStateOnChain{
          initiator_pubkey: Keys.pubkey(),
          responder_pubkey: Keys.pubkey(),
          delegates: list(Keys.pubkey()),
          total_amount: integer(),
          initiator_amount: integer(),
          responder_amount: integer(),
          lock_period: non_neg_integer(),
          closing_at: integer(),
          sequence: integer(),
          solo_sequence: integer(),
          state_hash: binary(),
          channel_reserve: non_neg_integer()
        }

  @type id :: binary()

  @pubkey_size Keys.pubkey_size()
  @nonce_size DataTx.nonce_size()

  @typedoc "Type of the errors returned by functions in this module"
  @type error :: {:error, String.t()}

  @doc """
  Definition of State Channel OnChain structure

  # Parameters
  - initiator_pubkey
  - responder_pubkey
  - delegates - list of delegates allowed to perform certain operations
  - total_amount - the total amount of tokens in the channel
  - initiator_amount - amount deposited by initiator in create_tx or from poi
  - responder_amount - amount deposited by responder in create_tx or from poi
  - lock_period - time before slashing is settled
  - closing_at - when != 0: block height when channel will be irrevocably closed
  - sequence - sequence of highest known fully signed offchain chainstate
  - solo_sequence - when !=0: sequence of first force progresses
  - state_hash - root hash of last known offchain chainstate
  - channel_reserve - minimal amount of tokens held by the initiator or responder
  """
  defstruct [
    :initiator_pubkey,
    :responder_pubkey,
    :delegates,
    :total_amount,
    :initiator_amount,
    :responder_amount,
    :lock_period,
    :closing_at,
    :sequence,
    :solo_sequence,
    :state_hash,
    :channel_reserve
  ]

  use Aecore.Util.Serializable

  @spec create(
          Keys.pubkey(),
          Keys.pubkey(),
          list(Keys.pubkey()),
          integer(),
          integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def create(
        initiator_pubkey,
        responder_pubkey,
        delegates,
        initiator_amount,
        responder_amount,
        lock_period,
        channel_reserve,
        state_hash
      ) do
    %ChannelStateOnChain{
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      delegates: delegates,
      total_amount: initiator_amount + responder_amount,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      lock_period: lock_period,
      closing_at: 0,
      sequence: 0,
      solo_sequence: 0,
      state_hash: state_hash,
      channel_reserve: channel_reserve
    }
  end

  @doc """
  Generates the channel id from a ChannelCreateTx.
  """
  @spec id(DataTx.t()) :: ChannelStateOnChain.id()
  def id(%DataTx{
        nonce: nonce,
        senders: [
          %Identifier{value: initiator_pubkey, type: account},
          %Identifier{value: responder_pubkey, type: account}
        ]
      }) do
    id(initiator_pubkey, responder_pubkey, nonce)
  end

  @doc """
  Generates the channel id from details of a ChannelCreateTx.
  """
  @spec id(Keys.pubkey(), Keys.pubkey(), non_neg_integer()) :: ChannelStateOnChain.id()
  def id(initiator_pubkey, responder_pubkey, nonce) do
    binary_data = <<
      initiator_pubkey::binary-size(@pubkey_size),
      nonce::size(@nonce_size),
      responder_pubkey::binary-size(@pubkey_size)
    >>

    Hash.hash(binary_data)
  end

  @spec pubkeys(ChannelStateOnChain.t()) :: {Keys.pubkey(), Keys.pubkey()}
  def pubkeys(%ChannelStateOnChain{
        initiator_pubkey: initiator_pubkey,
        responder_pubkey: responder_pubkey
      }) do
    {initiator_pubkey, responder_pubkey}
  end

  @spec is_peer?(ChannelStateOnChain.t(), Keys.pubkey()) :: boolean()
  def is_peer?(
        %ChannelStateOnChain{
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey
        },
        pubkey
      )
      when is_binary(pubkey) do
    pubkey in [initiator_pubkey, responder_pubkey]
  end

  @spec is_peer_or_delegate?(ChannelStateOnChain.t(), Keys.pubkey()) :: boolean()
  def is_peer_or_delegate?(
        %ChannelStateOnChain{
          initiator_pubkey: initiator_pubkey,
          responder_pubkey: responder_pubkey,
          delegates: delegates
        },
        pubkey
      )
      when is_binary(pubkey) do
    pubkey in [initiator_pubkey, responder_pubkey | delegates]
  end

  @doc """
  Returns true if the channel wasn't slashed. (Closed channels should be removed from the Channels state tree)
  """
  @spec active?(ChannelStateOnChain.t()) :: boolean()
  def active?(%ChannelStateOnChain{closing_at: 0}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  @doc """
  Returns true if the Channel can be settled. (If the Channel has been slashed and the current block height exceeds the locktime)
  """
  @spec settled?(ChannelStateOnChain.t(), non_neg_integer()) :: boolean()
  def settled?(%ChannelStateOnChain{closing_at: closing_at} = channel, block_height) do
    block_height >= closing_at && !active?(channel)
  end

  @doc """
  Validates SlashTx and SoloCloseTx payload and poi.
  """
  @spec validate_slashing(ChannelStateOnChain.t(), ChannelOffChainTx.t() | :empty, Poi.t()) ::
          :ok | error()
  def validate_slashing(
        %ChannelStateOnChain{} = channel,
        :empty,
        %Poi{} = poi
      ) do
    with {:ok, poi_initiator_amount, poi_responder_amount} <- balances_from_poi(channel, poi) do
      cond do
        # No payload is only allowed for SoloCloseTx
        channel.closing_at != 0 ->
          {:error,
           "#{__MODULE__}: Channel already slashed, sequence=#{channel.sequence}, closing at=#{
             channel.closing_at
           }"}

        channel.state_hash !== Poi.calculate_root_hash(poi) ->
          {:error,
           "#{__MODULE__}: Invalid state hash, expected #{inspect(channel.state_hash)}, got #{
             inspect(Poi.calculate_root_hash(poi))
           }"}

        channel.channel_reserve > poi_initiator_amount ->
          {:error,
           "#{__MODULE__}: Initiator balance in poi (#{poi_initiator_amount}) does not met channel reserve (#{
             channel.channel_reserve
           })"}

        channel.channel_reserve > poi_responder_amount ->
          {:error,
           "#{__MODULE__}: Responder balance in poi (#{poi_responder_amount}) does not met channel reserve (#{
             channel.channel_reserve
           })"}

        # initiator/responder amounts can only be trusted when sequence == 0
        channel.sequence == 0 and poi_initiator_amount != channel.initiator_amount ->
          {:error,
           "#{__MODULE__}: Invalid initiator amount, expected #{channel.initiator_amount}, got #{
             poi_initiator_amount
           }"}

        channel.sequence == 0 and poi_responder_amount != channel.responder_amount ->
          {:error,
           "#{__MODULE__}: Invalid responder amount, expected #{channel.responder_amount}, got #{
             poi_responder_amount
           }"}

        # if sequence != 0 and no ChannelOffChainTx was provided then deposits or withdraws modified the total amount
        poi_initiator_amount + poi_responder_amount != channel.total_amount ->
          {:error,
           "#{__MODULE__}: Invalid total amount, expected #{channel.total_amount}, got #{
             poi_initiator_amount + poi_responder_amount
           }"}

        true ->
          :ok
      end
    else
      {:error, _} = err ->
        err
    end
  end

  def validate_slashing(
        %ChannelStateOnChain{} = channel,
        %ChannelOffChainTx{} = offchain_tx,
        %Poi{} = poi
      ) do
    with {:ok, poi_initiator_amount, poi_responder_amount} <- balances_from_poi(channel, poi) do
      cond do
        offchain_tx.state_hash !== Poi.calculate_root_hash(poi) ->
          {:error,
           "#{__MODULE__}: Invalid state hash, expected #{inspect(offchain_tx.state_hash)}, got #{
             inspect(Poi.calculate_root_hash(poi))
           }"}

        channel.sequence > offchain_tx.sequence ->
          {:error,
           "#{__MODULE__}: OffChainTx is too old, expected newer than #{channel.sequence}, got #{
             offchain_tx.sequence
           }"}

        channel.channel_reserve > poi_initiator_amount ->
          {:error,
           "#{__MODULE__}: Initiator poi balance (#{poi_initiator_amount}) does not met channel reserve (#{
             channel.channel_reserve
           })"}

        channel.channel_reserve > poi_responder_amount ->
          {:error,
           "#{__MODULE__}: Responder poi balance (#{poi_responder_amount}) does not met channel reserve (#{
             channel.channel_reserve
           })"}

        poi_initiator_amount + poi_responder_amount != channel.total_amount ->
          {:error,
           "#{__MODULE__}: Invalid total amount, expected #{channel.total_amount}, got #{
             poi_initiator_amount + poi_responder_amount
           }"}

        true ->
          ChannelOffChainTx.verify_signatures(offchain_tx, pubkeys(channel))
      end
    else
      {:error, _} = err ->
        err
    end
  end

  @spec balances_from_poi(ChannelStateOnChain.t(), Poi.t()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | error()
  defp balances_from_poi(%ChannelStateOnChain{} = channel, %Poi{} = poi) do
    with {:ok, poi_initiator_amount} <- Poi.account_balance(poi, channel.initiator_pubkey),
         {:ok, poi_responder_amount} <- Poi.account_balance(poi, channel.responder_pubkey) do
      # Later we will need to factor in contracts
      {:ok, poi_initiator_amount, poi_responder_amount}
    else
      {:error, reason} ->
        {:error, "#{__MODULE__}: Poi is missing an OffChain account, #{reason}"}
    end
  end

  @doc """
  Executes slashing on a channel. Slashing should be validated beforehand with validate_slashing.
  """
  @spec apply_slashing(
          ChannelStateOnChain.t(),
          non_neg_integer(),
          ChannelOffChainTx.t() | :empty,
          Poi.t()
        ) :: ChannelStateOnChain.t()
  def apply_slashing(%ChannelStateOnChain{} = channel, block_height, :empty, %Poi{} = poi) do
    {:ok, initiator_amount} = Poi.account_balance(poi, channel.initiator_pubkey)
    {:ok, responder_amount} = Poi.account_balance(poi, channel.responder_pubkey)

    %ChannelStateOnChain{
      channel
      | initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        closing_at: block_height + channel.lock_period
    }
  end

  def apply_slashing(
        %ChannelStateOnChain{} = channel,
        block_height,
        %ChannelOffChainTx{state_hash: state_hash, sequence: sequence},
        %Poi{} = poi
      ) do
    {:ok, initiator_amount} = Poi.account_balance(poi, channel.initiator_pubkey)
    {:ok, responder_amount} = Poi.account_balance(poi, channel.responder_pubkey)

    %ChannelStateOnChain{
      channel
      | closing_at: block_height + channel.lock_period,
        sequence: sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount,
        state_hash: state_hash
    }
  end

  @spec validate_withdraw(
          ChannelStateOnChain.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok | error()
  def validate_withdraw(
        %ChannelStateOnChain{
          total_amount: total_amount,
          sequence: sequence,
          channel_reserve: channel_reserve
        },
        tx_amount,
        tx_sequence
      ) do
    cond do
      sequence >= tx_sequence ->
        {:error, "Too old state - latest known sequence is #{sequence} but we got #{tx_sequence}"}

      tx_amount < 0 ->
        {:error, "Withdraw of negative amount(#{tx_amount}) is forbidden"}

      total_amount - tx_amount < 2 * channel_reserve ->
        {:error,
         "New total amount of #{total_amount - tx_amount} is less than the minimum total amount of #{
           channel_reserve * 2
         }"}

      true ->
        :ok
    end
  end

  @spec apply_withdraw(
          ChannelStateOnChain.t(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def apply_withdraw(
        %ChannelStateOnChain{total_amount: total_amount} = channel,
        tx_amount,
        tx_sequence,
        tx_state_hash
      )
      when is_binary(tx_state_hash) do
    %ChannelStateOnChain{
      channel
      | total_amount: total_amount - tx_amount,
        sequence: tx_sequence,
        state_hash: tx_state_hash
    }
  end

  @spec validate_deposit(
          ChannelStateOnChain.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok | error()
  def validate_deposit(
        %ChannelStateOnChain{
          sequence: sequence
        },
        tx_amount,
        tx_sequence
      ) do
    cond do
      sequence >= tx_sequence ->
        {:error, "Too old state - latest known sequence is #{sequence} but we got #{tx_sequence}"}

      tx_amount < 0 ->
        {:error, "Deposit of negative amount(#{tx_amount}) is forbidden"}

      true ->
        :ok
    end
  end

  @spec apply_deposit(
          ChannelStateOnChain.t(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def apply_deposit(
        %ChannelStateOnChain{total_amount: total_amount} = channel,
        tx_amount,
        tx_sequence,
        tx_state_hash
      )
      when is_binary(tx_state_hash) do
    %ChannelStateOnChain{
      channel
      | total_amount: total_amount + tx_amount,
        sequence: tx_sequence,
        state_hash: tx_state_hash
    }
  end

  @doc """
  Validates the payload of ChannelSnapshotSoloTx.
  """
  @spec validate_snapshot(ChannelStateOnChain.t(), ChannelOffChainTx.t()) ::
          :ok | {:error, binary()}
  def validate_snapshot(
        %ChannelStateOnChain{} = channel,
        %ChannelOffChainTx{} = offchain_tx
      ) do
    cond do
      channel.sequence >= offchain_tx.sequence ->
        {:error,
         "#{__MODULE__}: OffChainTx is too old, expected newer than #{channel.sequence}, got #{
           offchain_tx.sequence
         }"}

      true ->
        ChannelOffChainTx.verify_signatures(offchain_tx, pubkeys(channel))
    end
  end

  @doc """
  Applies the provided payload of ChannelSnapshotSoloTx to the state of the channel. The contents should be validated by &validate_snapshot/2
  """
  @spec apply_snapshot(ChannelStateOnChain.t(), ChannelOffChainTx.t()) :: ChannelStateOnChain.t()
  def apply_snapshot(%ChannelStateOnChain{} = channel, %ChannelOffChainTx{
        sequence: sequence,
        state_hash: state_hash
      }) do
    %ChannelStateOnChain{
      channel
      | sequence: sequence,
        state_hash: state_hash
    }
  end

  @spec encode_to_list(ChannelStateOnChain.t()) :: list(binary())
  def encode_to_list(%ChannelStateOnChain{} = channel) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(channel.initiator_pubkey, :account),
      Identifier.create_encoded_to_binary(channel.responder_pubkey, :account),
      :binary.encode_unsigned(channel.total_amount),
      :binary.encode_unsigned(channel.initiator_amount),
      :binary.encode_unsigned(channel.responder_amount),
      :binary.encode_unsigned(channel.channel_reserve),
      Identifier.create_encoded_to_binary_list(channel.delegates, :account),
      channel.state_hash,
      :binary.encode_unsigned(channel.sequence),
      :binary.encode_unsigned(channel.solo_sequence),
      :binary.encode_unsigned(channel.lock_period),
      :binary.encode_unsigned(channel.closing_at)
    ]
  end

  @spec decode_from_list(integer(), list(binary())) :: {:ok, ChannelStateOnChain.t()} | error()
  def decode_from_list(@version, [
        encoded_initiator_pubkey,
        encoded_responder_pubkey,
        encoded_total_amount,
        encoded_initiator_amount,
        encoded_responder_amount,
        channel_reserve,
        encoded_delegates,
        state_hash,
        sequence,
        solo_sequence,
        lock_period,
        closing_at
      ]) do
    with {:ok, initiator_pubkey} <-
           Identifier.decode_from_binary_to_value(encoded_initiator_pubkey, :account),
         {:ok, responder_pubkey} <-
           Identifier.decode_from_binary_to_value(encoded_responder_pubkey, :account),
         {:ok, delegates} <-
           Identifier.decode_from_binary_list_to_value_list(encoded_delegates, :account) do
      {:ok,
       %ChannelStateOnChain{
         initiator_pubkey: initiator_pubkey,
         responder_pubkey: responder_pubkey,
         delegates: delegates,
         total_amount: :binary.decode_unsigned(encoded_total_amount),
         initiator_amount: :binary.decode_unsigned(encoded_initiator_amount),
         responder_amount: :binary.decode_unsigned(encoded_responder_amount),
         lock_period: :binary.decode_unsigned(lock_period),
         closing_at: :binary.decode_unsigned(closing_at),
         sequence: :binary.decode_unsigned(sequence),
         solo_sequence: :binary.decode_unsigned(solo_sequence),
         state_hash: state_hash,
         channel_reserve: :binary.decode_unsigned(channel_reserve)
       }}
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
