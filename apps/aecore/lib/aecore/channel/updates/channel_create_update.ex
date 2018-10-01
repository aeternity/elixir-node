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
          locktime: non_neg_integer()
        }

  @typedoc """
  The type of errors returned by this module
  """
  @type error :: {:error, binary()}

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
  defstruct [
    :initiator,
    :initiator_amount,
    :responder,
    :responder_amount,
    :channel_reserve,
    :locktime
  ]

  @doc """
  Creates a ChannelCreateUpdate from a ChannelCreateTx
  """
  @spec new(ChannelCreateTx.t(), Keys.pubkey(), Keys.pubkey()) :: ChannelCreateUpdate.t()
  def new(
        %ChannelCreateTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount,
          channel_reserve: channel_reserve,
          locktime: locktime
        },
        initiator,
        responder
      )
      when is_binary(initiator) and is_binary(responder) do
    %ChannelCreateUpdate{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
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
    raise {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  @doc """
  ChannelCreateUpdate cannot be serialized into ChannelOffchainTx.
  """
  @spec encode_to_list(ChannelCreateUpdate.t()) :: error()
  def encode_to_list(_) do
    raise {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  @doc """
  Creates the initial chainstate. Assumes no chainstate is present. Returns an error in the creation failed or a chainstate is already present.
  """
  @spec update_offchain_chainstate(Chainstate.t() | nil, ChannelCreateUpdate.t()) ::
          {:ok, Chainstate.t()} | error()
  def update_offchain_chainstate(
        nil,
        %ChannelCreateUpdate{
          initiator: initiator,
          initiator_amount: initiator_amount,
          responder: responder,
          responder_amount: responder_amount
        },
        channel_reserve
      ) do
    Enum.reduce_while(
      [
        {initiator, initiator_amount},
        {responder, responder_amount}
      ],
      {:ok, Chainstate.create_chainstate_trees()},
      fn account_specification, {:ok, chainstate} ->
        case create_account_in_chainstate(account_specification, chainstate, channel_reserve) do
          {:ok, _} = new_acc ->
            {:cont, new_acc}

          {:error, _} = err ->
            {:halt, err}
        end
      end
    )
  end

  @spec create_account_in_chainstate(tuple(), Chainstate.t() | nil, non_neg_integer()) ::
          {:ok, Chainstate.t()} | error()
  defp create_account_in_chainstate(
         {pubkey, amount},
         %Chainstate{accounts: accounts} = chainstate,
         channel_reserve
       ) do
    case AccountStateTree.safe_update(
           accounts,
           pubkey,
           &setup_initial_account(&1, amount, channel_reserve)
         ) do
      {:ok, updated_accounts} ->
        {:ok,
         %Chainstate{
           chainstate
           | accounts: updated_accounts
         }}

      {:error, _} = err ->
        err
    end
  end

  @spec setup_initial_account(Account.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Account.t()} | error()
  defp setup_initial_account(account, amount, channel_reserve) do
    with {:ok, account1} <- Account.apply_transfer(account, nil, amount),
         :ok <- ChannelOffChainUpdate.ensure_channel_reserve_is_met(account1, channel_reserve) do
      {:ok, account1}
    else
      {:error, _} = err ->
        err
    end
  end

  def update_offchain_chainstate(%Chainstate{}, _) do
    {:error, "#{__MODULE__}: The create update may only be aplied once"}
  end

  @spec half_signed_preprocess_check(ChannelCreateUpdate.t(), map()) :: :ok | error()
  def half_signed_preprocess_check(
        %ChannelCreateUpdate{
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
        }
      ) do
    cond do
      initiator == responder ->
        {:error, "#{__MODULE__}: Initiator and responder cannot be the same"}

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
    {:error,
     "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end
end
