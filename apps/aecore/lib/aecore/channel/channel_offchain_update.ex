defmodule Aecore.Channel.ChannelOffchainUpdate do
  @moduledoc """
  Behaviour that states all the necessary functions that every update of the offchain state should implement.
  """

  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account

  @typedoc "Structure of an update"
  @type update_types ::
          Aecore.Channels.Updates.ChannelTransferUpdate.t()
          | Aecore.Channels.Updates.ChannelDepositUpdate.t()
          | Aecore.Channels.Updates.ChannelWidthdrawUpdate.t()

  # Callbacks

  @doc """
    Updates
  """
  @callback update_offchain_chainstate(Chainstate.t(), update_types(), non_neg_integer()) :: {:ok, Chainstate.t()} | {:error, String.t()}

  @callback encode_to_list(update_types()) :: list(binary()) | {:error, String.t()}

  @callback decode_from_list(list(binary())) :: update_types()

  @doc """
      Epoch 0.16 does not treat updates as standard serializable objects but this changed in the later versions.
      To make upgrading easy updates will need to specify their ID which will act as their tag. To upgrade
      to a recent version of epoch offchain updates will just need to be added as serializable objects to the serializer
      and this temporary tag will need to be removed.
    """

  def tag_to_module(0), do: {:ok, Aecore.Channel.Updates.ChannelTransferUpdate}
  def tag_to_module(1), do: {:ok, Aecore.Channel.Updates.ChannelDepositUpdate}
  def tag_to_module(2), do: {:ok, Aecore.Channel.Updates.ChannelWidthdrawUpdate}
  def tag_to_module(_), do: {:error, "#{__MODULE__} Error: Invalid update tag"}

  def module_to_tag(Aecore.Channel.Updates.ChannelTransferUpdate), do: {:ok, 0}
  def module_to_tag(Aecore.Channel.Updates.ChannelDepositUpdate), do: {:ok, 1}
  def module_to_tag(Aecore.Channel.Updates.ChannelWidthdrawUpdate), do: {:ok, 2}
  def module_to_tag(module), do: {:error, "#{__MODULE__} Error: Unserializable module: #{IO.inspect(module)}"}

  @spec to_list(update_types()) :: list(binary())
  def to_list(object) do
    module = object.__struct__
    {:ok, tag} = module_to_tag(module)
    [:binary.encode_unsigned(tag)] ++ module.encode_to_list(object)
  end

  @spec from_list(list(binary())) :: update_types()
  def from_list([tag | rest]) do
    decoded_tag = :binary.decode_unsigned(tag)
    case tag_to_module(decoded_tag) do
      {:ok, module} ->
        module.decode_from_list(rest)
      {:error, _} = err ->
        err
    end
  end

  @spec update_chainstate(Chainstate.t() | nil, update_types(), non_neg_integer()) :: {:ok, Chainstate.t()} | {:error, String.t()}
  defp update_chainstate(chainstate, object, channel_reserve) do
    module = object.__struct__
    module.update_offchain_chainstate(chainstate, object, channel_reserve)
  end

  @spec apply_updates(Chainstate.t() | nil, list(update_types()), non_neg_integer()) :: {:ok, Chainstate.t()} | {:error, String.t()}
  def apply_updates(chainstate, updates, channel_reserve) do
    new_chainstate =
      Enum.reduce_while(updates, chainstate,
        fn update, acc ->
          case update_chainstate(acc, update, channel_reserve) do
            {:ok, new_acc} ->
              {:cont, new_acc}
            {:error, _} = err ->
              {:halt, err}
          end
        end)
    case new_chainstate do
      {:error, _} = err ->
        err
      _ ->
        {:ok, new_chainstate}
    end
  end

  def ensure_channel_reserve_is_meet!(%Account{balance: balance} = account, channel_reserve) do
    if(balance < channel_reserve) do
      throw {:error, "#{__MODULE__} Account does not meet minimal deposit (We have #{balance} tokens vs minimal deposit of #{channel_reserve} tokens)"}
    end
    account
  end
end
