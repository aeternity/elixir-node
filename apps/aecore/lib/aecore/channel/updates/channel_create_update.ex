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
  @spec update_offchain_chainstate!(Chainstate.t() | nil, ChannelCreateUpdate.t()) ::
          Chainstate.t() | no_return()
  def update_offchain_chainstate!(nil, %ChannelCreateUpdate{
        initiator: initiator,
        initiator_amount: initiator_amount,
        responder: responder,
        responder_amount: responder_amount
      }) do
    Enum.reduce(
      [
        {initiator, initiator_amount},
        {responder, responder_amount}
      ],
      Chainstate.create_chainstate_trees(),
      &create_account_in_chainstate!/2
    )
  end

  def update_offchain_chainstate!(%Chainstate{}, _) do
    raise {:error, "#{__MODULE__}: The create update may only be applied once"}
  end

  @spec create_account_in_chainstate!(tuple(), Chainstate.t() | nil) ::
          Chainstate.t() | no_return()
  defp create_account_in_chainstate!(
         {pubkey, amount},
         %Chainstate{accounts: accounts} = chainstate
       ) do
    updated_accounts =
      AccountStateTree.update(
        accounts,
        pubkey,
        &setup_initial_account!(&1, amount)
      )

    %Chainstate{
      chainstate
      | accounts: updated_accounts
    }
  end

  @spec setup_initial_account!(Account.t(), non_neg_integer()) :: Account.t() | no_return()
  defp setup_initial_account!(account, amount) do
    Account.apply_transfer!(account, nil, amount)
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
        {:error,
         "#{__MODULE__}: Wrong initiator, expected #{inspect(correct_initiator)}, got #{
           inspect(initiator)
         }"}

      initiator_amount != correct_initiator_amount ->
        {:error,
         "#{__MODULE__}: Wrong initiator amount, expected #{correct_initiator_amount}, got #{
           initiator_amount
         }"}

      responder != correct_responder ->
        {:error,
         "#{__MODULE__}: Wrong responder, expected #{inspect(correct_responder)}, got #{
           inspect(responder)
         }"}

      responder_amount != correct_responder_amount ->
        {:error,
         "#{__MODULE__}: Wrong responder amount, expected #{correct_responder_amount}, got #{
           responder_amount
         }"}

      channel_reserve != correct_channel_reserve ->
        {:error,
         "#{__MODULE__}: Wrong channel reserve, expected #{correct_channel_reserve}, got #{
           channel_reserve
         }"}

      locktime != correct_locktime ->
        {:error, "#{__MODULE__}: Wrong locktime, expected #{correct_locktime}, got #{locktime}"}

      initiator_amount < 0 ->
        {:error, "#{__MODULE__}: Initiator balance cannot be negative"}

      responder_amount < 0 ->
        {:error, "#{__MODULE__}: Responder balance cannot be negative"}

      channel_reserve < 0 ->
        {:error, "#{__MODULE__}: Channel reserve cannot be negative"}

      locktime < 0 ->
        {:error, "#{__MODULE__}: Channel locktime cannot be negative"}

      initiator_amount < channel_reserve ->
        {:error, "#{__MODULE__}: Initiator does not met channel reserve"}

      responder_amount < channel_reserve ->
        {:error, "#{__MODULE__}: Responder does not met channel reserve"}

      true ->
        :ok
    end
  end

  def half_signed_preprocess_check(%ChannelCreateUpdate{}, _) do
    {:error,
     "#{__MODULE__}: Missing keys in the opts dictionary. This probably means that the update was unexpected."}
  end

  @doc """
  Validates an update considering state before applying it to the provided chainstate.
  """
  @spec fully_signed_preprocess_check(
          Chainstate.t() | nil,
          ChannelCreateUpdate.t(),
          non_neg_integer()
        ) :: :ok | error()

  def fully_signed_preprocess_check(nil, %ChannelCreateUpdate{}, _channel_reserve) do
    :ok
  end

  def fully_signed_preprocess_check(%Chainstate{}, %ChannelCreateUpdate{}, _channel_reserve) do
    {:error, "#{__MODULE__}: The create update may only be applied once"}
  end
end
