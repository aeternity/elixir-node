defmodule Aecore.Channel.ChannelOffChainUpdate do
  @moduledoc """
  Behaviour that states all the necessary functions that every update of the offchain state should implement.
  This module implements helpers for applying updates to an offchain chainstate
  """

  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account

  alias Aecore.Channel.Updates.ChannelTransferUpdate
  alias Aecore.Channel.Updates.ChannelDepositUpdate
  alias Aecore.Channel.Updates.ChannelWidthdrawUpdate

  @typedoc """
  Possible types of an update
  """
  @type update_types ::
          ChannelTransferUpdate.t()
          | ChannelDepositUpdate.t()
          | ChannelWidthdrawUpdate.t()

  @typedoc """
  The type of errors returned by the functions in this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Callback for aplying the update to the offchain chainstate.
  """
  @callback update_offchain_chainstate(Chainstate.t(), update_types(), non_neg_integer()) ::
              {:ok, Chainstate.t()} | error()

  @doc """
  Encodes the update to list of binaries. This callback is compatible with the Serializable behaviour.
  Epoch 0.16 does not treat updates as standard serializable objects but this changed in the later versions.
  """
  @callback encode_to_list(update_types()) :: list(binary()) | error()

  @doc """
  Decodes the update from a list of binaries. This callback is compatible with the Serializable behaviour.
  Epoch 0.16 does not treat updates as standard serializable objects but this changed in the later versions.
  """
  @callback decode_from_list(list(binary())) :: update_types()

  @doc """
  Preprocess checks for an incoming half signed update.
  This callback should check for signs of the update being malicious(for instance transfer updates should validate if the transfer is in the correct direction).
  The provided map contains values to check against.
  """
  @callback half_signed_preprocess_check(update_types(), map()) :: :ok | error()

  @doc """
  Epoch 0.16 does not treat updates as standard serializable objects but this changed in the later versions.
  To make upgrading easy updates will need to specify their ID which will act as their tag. To upgrade
  to a recent version of epoch offchain updates will just need to be added as serializable objects to the serializer
  and this temporary tag will need to be removed.
  """
  @spec tag_to_module(non_neg_integer()) :: module()
  def tag_to_module(0), do: {:ok, ChannelTransferUpdate}
  def tag_to_module(1), do: {:ok, ChannelDepositUpdate}
  def tag_to_module(2), do: {:ok, ChannelWidthdrawUpdate}

  def tag_to_module(_), do: {:error, "#{__MODULE__} Error: Invalid update tag"}

  @doc """
  Converts the specified module to the associated tag.
  """
  @spec module_to_tag(module()) :: non_neg_integer()
  def module_to_tag(ChannelTransferUpdate), do: {:ok, 0}
  def module_to_tag(ChannelDepositUpdate), do: {:ok, 1}
  def module_to_tag(ChannelWidthdrawUpdate), do: {:ok, 2}

  def module_to_tag(module),
    do: {:error, "#{__MODULE__} Error: Unserializable module: #{inspect(module)}"}

  @doc """
  Encodes the given update to a list of binaries.
  """
  @spec encode_to_list(update_types()) :: list(binary())
  def encode_to_list(object) do
    module = object.__struct__
    {:ok, tag} = module_to_tag(module)
    [:binary.encode_unsigned(tag)] ++ module.encode_to_list(object)
  end

  @doc """
  Decodes the given update from a list of binaries.
  """
  @spec decode_from_list(list(binary())) :: update_types() | error()
  def decode_from_list([tag | rest]) do
    decoded_tag = :binary.decode_unsigned(tag)

    case tag_to_module(decoded_tag) do
      {:ok, module} ->
        module.decode_from_list(rest)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Updates the offchain chainstate acording to the specified update.
  """
  @spec update_offchain_chainstate(Chainstate.t() | nil, update_types(), non_neg_integer()) ::
          {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(chainstate, object, channel_reserve) do
    module = object.__struct__
    module.update_offchain_chainstate(chainstate, object, channel_reserve)
  end

  # Function passed to Enum.reduce. Aplies the given update to the chainstate.
  @spec apply_single_update_to_chainstate(
          update_types(),
          {:ok, Chainstate.t() | nil},
          non_neg_integer()
        ) :: {:ok, Chainstate.t()} | {:halt, error()}
  defp apply_single_update_to_chainstate(update, {:ok, chainstate}, channel_reserve) do
    case update_offchain_chainstate(chainstate, update, channel_reserve) do
      {:ok, _} = updated_chainstate ->
        {:cont, updated_chainstate}

      {:error, _} = err ->
        {:halt, err}
    end
  end

  @doc """
  Applies each update in a list of updates to the offchain chainstate. Breaks on the first encountered error.
  """
  @spec apply_updates(Chainstate.t() | nil, list(update_types()), non_neg_integer()) ::
          {:ok, Chainstate.t()} | error()
  def apply_updates(chainstate, updates, channel_reserve) do
    Enum.reduce_while(
      updates,
      {:ok, chainstate},
      &apply_single_update_to_chainstate(&1, &2, channel_reserve)
    )
  end

  @doc """
  Makes sure that for the given account the channel reserve was meet
  """
  @spec ensure_channel_reserve_is_met(Account.t(), non_neg_integer()) :: :ok | error()
  def ensure_channel_reserve_is_met(%Account{balance: balance}, channel_reserve) do
    if balance < channel_reserve do
      {:error,
       "#{__MODULE__} Account does not met channel reserve (We have #{balance} tokens vs channel reserve of #{
         channel_reserve
       } tokens)"}
    else
      :ok
    end
  end

  @doc """
  Runs preprocess checks for an update which was signed by the foreign peer in the channel.
  """
  @spec half_signed_preprocess_check(update_types(), map()) :: :ok | error()
  def half_signed_preprocess_check(update, opts) do
    module = update.__struct__
    module.half_signed_preprocess_check(update, opts)
  end
end
