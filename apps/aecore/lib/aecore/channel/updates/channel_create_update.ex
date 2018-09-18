defmodule Aecore.Channel.Updates.ChannelCreateUpdate do
  @moduledoc """
  State channel update which creates the offchain chainstate. This update can not be included in ChannelOffchainTx.
  The creation of the initial chainstate is implemented as an update in order to increase readibility of the code and facilitate code reuse.
  """

  alias Aecore.Channel.Updates.ChannelCreateUpdate
  alias Aecore.Channel.ChannelOffChainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account
  alias Aecore.Channel.Tx.ChannelCreateTx

  @behaviour ChannelOffChainUpdate

  @typedoc """
  Structure of the ChannelCreateUpdate type
  """
  @type t :: %ChannelCreateUpdate{
          initiator: binary(),
          initiator_amount: non_neg_integer(),
          responder: binary(),
          responder_amount: non_neg_integer(),
          channel_reserve: non_neg_integer(),
          locktime: non_neg_integer(),
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, String.t()}

  @doc """
  Definition of ChannelCreateUpdate structure

  ## Parameters
  - initiator: initiator of the channel creation
  - initiator_amount: amount that the initiator account commits
  - responder: responder of the channel creation
  - responder_amount: amount that the responder account commits
  - channel_reserve: the reserve of the channel
  - locktime: amount of blocks before disputes are settled
  """
  defstruct [:initiator, :initiator_amount, :responder, :responder_amount, :channel_reserve, :locktime]

  @doc """
  Creates a ChannelCreateUpdate from a ChannelCreateTx
  """
  @spec new(ChannelCreateTx.t()) :: ChannelCreateUpdate.t()
  def new(%ChannelCreateTx{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
      responder_amount: responder_amount,
      channel_reserve: channel_reserve,
      locktime: locktime}) do
    %ChannelCreateUpdate{
      initiator: initiator.value,
      initiator_amount: initiator_amount,
      responder: responder.value,
      responder_amount: responder_amount,
      channel_reserve: channel_reserve,
      locktime: locktime
    }
  end

  @doc """
  ChannelCreateUpdate MUST not be included in ChannelOffchainTx. This update may only be created from ChannelCreateTx.
  """
  @spec decode_from_list(list(binary())) :: error()
  def decode_from_list(_) do
    {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  @doc """
  ChannelCreateUpdate cannot be serialized into ChannelOffchainTx.
  """
  @spec encode_to_list(ChannelCreateUpdate.t()) :: error()
  def encode_to_list(_) do
    {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  @spec create_account_in_chainstate(tuple(), Chainstate.t() | nil, non_neg_integer()) :: Chainstate.t()
  defp create_account_in_chainstate({pubkey, amount}, %Chainstate{accounts: accounts} = chainstate, channel_reserve) do
    account =
      Account.empty
      |> Account.apply_transfer!(nil, amount)
      |> ChannelOffChainUpdate.ensure_channel_reserve_is_meet!(channel_reserve)
    %Chainstate{
      chainstate
      | accounts: AccountStateTree.put(accounts, pubkey, account)
    }
  end

  @doc """
  Creates the initial chainstate. Assumes no chainstate is present. Returns an error in the creation failed or a chainstate is already present.
  """
  @spec update_offchain_chainstate(Chainstate.t() | nil, ChannelCreateUpdate.t()) :: {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(nil,
        %ChannelCreateUpdate{
          initiator: initiator,
          initiator_amount: initiator_amount,
          responder: responder,
          responder_amount: responder_amount
        },
        channel_reserve) do
    initial_chainstate = Enum.reduce(
      [
        {initiator, initiator_amount},
        {responder, responder_amount}
      ],
      Chainstate.create_chainstate_trees(),
      &create_account_in_chainstate(&1, &2, channel_reserve)
    )
    {:ok, initial_chainstate}
  catch
    {:error, _} = err ->
      err
  end

  def update_offchain_chainstate(%Chainstate{}, _) do
    {:error, "#{__MODULE__}: The create update may only be aplied once"}
  end

  @spec half_signed_preprocess_check(ChannelCreateUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(%ChannelCreateUpdate{
          initiator: initiator,
          initiator_amount: initiator_amount,
          responder: responder,
          responder_amount: responder_amount,
          channel_reserve: channel_reserve,
          locktime: locktime
        },
        %{
          our_pubkey: correct_responder,
          responder_amount: correct_responder_amount,
          foreign_pubkey: correct_initiator,
          initiator_amount: correct_initiator_amount,
          channel_reserve: correct_channel_reserve,
          locktime: correct_locktime
        }) do
    cond do
      initiator != correct_initiator ->
        {:error, "#{__MODULE__}: Wrong initiator"}

      initiator_amount != correct_initiator_amount ->
        {:error, "#{__MODULE__}: Wrong initiator amount"}

      responder != correct_responder ->
        {:error, "#{__MODULE__}: Wrong responder"}

      responder_amount != correct_responder_amount ->
        {:error, "#{__MODULE__}: Wrong responder amount"}

      channel_reserve != correct_channel_reserve ->
        {:error, "#{__MODULE__}: Wrong channel reserve"}

      locktime != correct_locktime ->
        {:error, "#{__MODULE__}: Wrong locktime}"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelCreateUpdate{}, _) do
    {:error, "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end
end
