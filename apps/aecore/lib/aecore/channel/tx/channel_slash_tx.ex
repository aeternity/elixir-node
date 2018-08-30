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

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelSlash Transaction"
  @type payload :: %{
          offchain_tx: map(),
          poi: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelSlash Transaction type"
  @type t :: %ChannelSlashTx{
          offchain_tx: ChannelOffchainTx.t(),
          poi: Poi.t()
        }

  @doc """
  Definition of Aecore ChannelSlashTx structure

  ## Parameters
  - state - the state to slash with
  """
  defstruct [:offchain_tx, :poi]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{ofchain_tx: offchain_tx, poi: poi} = _payload) do
    %ChannelSlashTx{
      offchain_tx: ChannelOffchainTx.init(offchain_tx),
      poi: Poi.init(poi)
    }
  end

  @spec create(ChannelOffchainTx.t(), Chainstate.t()) :: ChannelSlashTx.t()
  def create(offchain_tx, chainstate) do
    poi =
      PatriciaMerkleTree.all_keys(chainstate.accounts)
      |> Enum.reduce(Poi.construct(chainstate),
        fn(pub_key, acc) ->
          {:ok, new_acc} = Poi.add_to_poi(:accounts, pub_key, chainstate, acc)
          new_acc
        end)

    %ChannelSlashTx{
      offchain_tx: offchain_tx,
      poi: poi
    }
  end

  @spec sequence(ChannelSlashTx.t()) :: non_neg_integer()
  def sequence(%ChannelSlashTx{offchain_tx: %ChannelOffchainTx{sequence: sequence}}), do: sequence

  @spec channel_id(ChannelSlashTx.t()) :: binary()
  def channel_id(%ChannelSlashTx{offchain_tx: %ChannelOffchainTx{channel_id: id}}), do: id

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSlashTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSlashTx{offchain_tx: %ChannelOffchainTx{sequence: sequence, state_hash: state_hash}, poi: poi}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders size"}

      sequence == 0 ->
        {:error, "#{__MODULE__}: Can't slash with zero state"}

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
          offchain_tx:
            %ChannelOffchainTx{
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
        %ChannelSlashTx{offchain_tx: state},
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
    main_sender = DataTx.main_sender(datatx)
    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(tx.offchain_tx.channel_id),
      Identifier.encode_to_binary(main_sender),
      ChannelOffchainTx.encode_to_payload(tx.offchain_tx),
      Serialization.rlp_encode(tx.poi),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.nonce)
    ]
  end

  def decode_from_list(@version, [_, encoded_sender, payload, rlp_encoded_poi, ttl, fee, nonce]) do
    case ChannelOffchainTx.decode_from_payload(payload) do
      {:ok, offchain_tx} ->
        case Serialization.rlp_decode_only(rlp_encoded_poi, Poi) do
          {:ok, poi} ->
            DataTx.init_binary(
              ChannelSlashTx,
              %ChannelSlashTx{
                offchain_tx: offchain_tx,
                poi: poi
              },
              encoded_sender,
              :binary.encode_unsigned(fee),
            :binary.encode_unsigned(nonce),
            :binary.encode_unsigned(ttl)
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
