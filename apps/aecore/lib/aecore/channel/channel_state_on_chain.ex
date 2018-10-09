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

  @pubkey_size Keys.pubkey_size()
  @nonce_size DataTx.nonce_size()

  @doc """
  Definition of State Channel OnChain structure

  # Parameters
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

  use Aecore.Util.Serializable

  @spec create(
          Keys.pubkey(),
          Keys.pubkey(),
          integer(),
          integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def create(
        initiator_pubkey,
        responder_pubkey,
        initiator_amount,
        responder_amount,
        lock_period,
        channel_reserve,
        state_hash
      ) do
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
  Generates the channel id from a ChannelCreateTx.
  """
  @spec id(DataTx.t()) :: id()
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
  @spec id(Keys.pubkey(), Keys.pubkey(), non_neg_integer()) :: id()
  def id(initiator_pubkey, responder_pubkey, nonce) do
    binary_data = <<
      initiator_pubkey::binary-size(@pubkey_size),
      nonce::size(@nonce_size),
      responder_pubkey::binary-size(@pubkey_size)
    >>

    Hash.hash(binary_data)
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
  Returns true if the channel wasn't slashed. (Closed channels should be removed from the Channels state tree)
  """
  @spec active?(ChannelStateOnChain.t()) :: boolean()
  def active?(%ChannelStateOnChain{slash_close: 0}) do
    true
  end

  def active?(%ChannelStateOnChain{}) do
    false
  end

  @doc """
  Returns true if the Channel can be settled. (If the Channel has been slashed and the current block height exceeds the locktime)
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
    with {:ok, poi_initiator_amount, poi_responder_amount} <- balances_from_poi(channel, poi) do
      cond do
        # No payload is only allowed for SoloCloseTx
        channel.slash_sequence != 0 ->
          {:error, "#{__MODULE__}: Channel already slashed"}

        channel.state_hash !== Poi.calculate_root_hash(poi) ->
          {:error, "#{__MODULE__}: Invalid state hash"}

        channel.channel_reserve > poi_initiator_amount ->
          {:error, "#{__MODULE__}: Initiator does not met channel reserve"}

        channel.channel_reserve > poi_responder_amount ->
          {:error, "#{__MODULE__}: Responder does not met channel reserve"}

        poi_initiator_amount !== channel.initiator_amount ->
          {:error, "#{__MODULE__}: Invalid initiator amount"}

        poi_responder_amount !== channel.responder_amount ->
          {:error, "#{__MODULE__}: Invalid responder amount"}

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
          {:error, "#{__MODULE__}: Invalid state hash"}

        channel.slash_sequence >= offchain_tx.sequence ->
          {:error, "#{__MODULE__}: OffChain state is too old"}

        channel.channel_reserve > poi_initiator_amount ->
          {:error, "#{__MODULE__}: Initiator does not met channel reserve"}

        channel.channel_reserve > poi_responder_amount ->
          {:error, "#{__MODULE__}: Responder does not met channel reserve"}

        poi_initiator_amount + poi_responder_amount !==
            channel.initiator_amount + channel.responder_amount ->
          {:error, "#{__MODULE__}: Invalid total amount"}

        true ->
          ChannelOffChainTx.verify_signatures(offchain_tx, pubkeys(channel))
      end
    else
      {:error, _} = err ->
        err
    end
  end

  @spec balances_from_poi(ChannelStateOnChain.t(), Poi.t()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, binary()}
  defp balances_from_poi(%ChannelStateOnChain{} = channel, %Poi{} = poi) do
    with {:ok, poi_initiator_amount} <- Poi.account_balance(poi, channel.initiator_pubkey),
         {:ok, poi_responder_amount} <- Poi.account_balance(poi, channel.responder_pubkey) do
      # Later we will need to factor in contracts
      {:ok, poi_initiator_amount, poi_responder_amount}
    else
      {:error, _} ->
        {:error, "#{__MODULE__}: Poi is missing an OffChain account."}
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
        slash_close: block_height + channel.lock_period,
        slash_sequence: 0
    }
  end

  def apply_slashing(
        %ChannelStateOnChain{} = channel,
        block_height,
        %ChannelOffChainTx{} = offchain_tx,
        %Poi{} = poi
      ) do
    {:ok, initiator_amount} = Poi.account_balance(poi, channel.initiator_pubkey)
    {:ok, responder_amount} = Poi.account_balance(poi, channel.responder_pubkey)

    %ChannelStateOnChain{
      channel
      | slash_close: block_height + channel.lock_period,
        slash_sequence: offchain_tx.sequence,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
    }
  end

  @spec validate_withdraw(
          ChannelStateOnChain.t(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok | {:error, binary()}
  def validate_withdraw(
        %ChannelStateOnChain{slash_sequence: slash_sequence, channel_reserve: channel_reserve} =
          channel,
        tx_account,
        tx_amount,
        tx_sequence
      ) do
    amount_atom = amount_atom_for_account(tx_account)

    cond do
      slash_sequence >= tx_sequence ->
        {:error, "Too old state"}

      amount_atom == :error ->
        {:error, "Withdraw destination must be a party of this channel"}

      Map.get(channel, amount_atom) - tx_amount < channel_reserve ->
        {:error, "The withdrawn account does not met channel reserve"}

      true ->
        :ok
    end
  end

  @spec apply_withdraw(
          ChannelStateOnChain.t(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def apply_withdraw(
        %ChannelStateOnChain{} = channel,
        tx_account,
        tx_amount,
        tx_sequence,
        tx_state_hash
      )
      when is_binary(tx_account) and is_binary(tx_state_hash) do
    case amount_atom_for_account(channel, tx_account) do
      amount_atom ->
        updated_channel =
          Map.update(channel, amount_atom, fn cur_amount -> cur_amount - tx_amount end)

        %ChannelStateOnChain{
          updated_channel
          | slash_sequence: tx_sequence,
            state_hash: tx_state_hash
        }

      :error ->
        raise {:error,
               "This should never happen. Make sure &validate_withdraw/1 was called before."}
    end
  end

  @spec validate_deposit(
          ChannelStateOnChain.t(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok | {:error, binary()}
  def validate_deposit(
        %ChannelStateOnChain{slash_sequence: slash_sequence} = channel,
        tx_account,
        tx_amount,
        tx_sequence
      )
      when is_binary(tx_account) do
    amount_atom = amount_atom_for_account(tx_account)

    cond do
      slash_sequence >= tx_sequence ->
        {:error, "Too old state"}

      amount_atom == :error ->
        {:error, "Deposit destination must be a party of this channel"}

      true ->
        :ok
    end
  end

  @spec apply_deposit(
          ChannelStateOnChain.t(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          binary()
        ) :: ChannelStateOnChain.t()
  def apply_deposit(
        %ChannelStateOnChain{} = channel,
        tx_account,
        tx_amount,
        tx_sequence,
        tx_state_hash
      )
      when is_binary(tx_account) and is_binary(tx_state_hash) do
    case amount_atom_for_account(channel, tx_account) do
      amount_atom ->
        updated_channel =
          Map.update(channel, amount_atom, fn cur_amount -> cur_amount + tx_amount end)

        %ChannelStateOnChain{
          updated_channel
          | slash_sequence: tx_sequence,
            state_hash: tx_state_hash
        }

      :error ->
        raise {:error,
               "This should never happen. Make sure &validate_deposit/1 was called before."}
    end
  end

  @spec amount_atom_for_account(ChannelStateOnChain.t(), Keys.pubkey()) ::
          :initiator_amount | :responder_amount | :error
  defp amount_atom_for_account(
         %ChannelStateOnChain{initiator: initiator, responder: responder},
         account
       )
       when is_binary(account) do
    cond do
      initiator == account ->
        :initiator_amount

      responder == account ->
        :responder_amount

      true ->
        :error
    end
  end

  @spec encode_to_list(ChannelStateOnChain.t()) :: list() | {:error, String.t()}
  def encode_to_list(%ChannelStateOnChain{} = channel) do
    total_amount = channel.initiator_amount + channel.responder_amount

    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(channel.initiator_pubkey, :account),
      Identifier.create_encoded_to_binary(channel.responder_pubkey, :account),
      :binary.encode_unsigned(total_amount),
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
        encoded_initiator_pubkey,
        encoded_responder_pubkey,
        total_amount,
        initiator_amount,
        channel_reserve,
        state_hash,
        slash_sequence,
        lock_period,
        slash_close
      ]) do
    responder_amount =
      :binary.decode_unsigned(total_amount) - :binary.decode_unsigned(initiator_amount)

    with {:ok, initiator_pubkey} <-
           Identifier.decode_from_binary_to_value(encoded_initiator_pubkey, :account),
         {:ok, responder_pubkey} <-
           Identifier.decode_from_binary_to_value(encoded_responder_pubkey, :account) do
      {:ok,
       %ChannelStateOnChain{
         initiator_pubkey: initiator_pubkey,
         responder_pubkey: responder_pubkey,
         initiator_amount: :binary.decode_unsigned(initiator_amount),
         responder_amount: responder_amount,
         lock_period: :binary.decode_unsigned(lock_period),
         slash_close: :binary.decode_unsigned(slash_close),
         slash_sequence: :binary.decode_unsigned(slash_sequence),
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
