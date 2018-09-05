defmodule Aecore.Channel.Updates.ChannelCreateUpdate do
  @moduledoc """
    State channel update which creates the offchain chainstate. This update can not be included in ChannelOffchainTx.
    The creation of the initial chainstate is implemented as an update in order to increase readibility of the code and facilitate code reuse.
  """

  alias Aecore.Channel.Updates.ChannelCreateUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account
  alias Aecore.Channel.Tx.ChannelCreateTx

  @behaviour ChannelOffchainUpdate

  @typedoc """
    Structure of the ChannelCreateUpdate type
  """
  @type t :: %ChannelCreateUpdate{
          initiator: Identifier.t(),
          initiator_amount: non_neg_integer(),
          responder: Identifier.t(),
          responder_amount: non_neg_integer()
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
  """
  defstruct [:initiator, :initiator_amount, :responder, :responder_amount]

  @doc """
    Creates a ChannelCreateUpdate from a ChannelCreateTx
  """
  @spec new(ChannelCreateTx.t()) :: ChannelCreateUpdate.t()
  def new(%ChannelCreateTx{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
      responder_amount: responder_amount}) do
    %ChannelCreateUpdate{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
      responder_amount: responder_amount
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
    new_chainstate = Enum.reduce(
      [
        {initiator, initiator_amount},
        {responder, responder_amount}
      ],
      Chainstate.create_chainstate_trees(),
      fn {pubkey, amount}, acc ->
        account =
          Account.empty
          |> Account.apply_transfer!(nil, amount)
          |> ChannelOffchainUpdate.ensure_channel_reserve_is_meet!(channel_reserve)
        %Chainstate{
          acc
          | accounts: AccountStateTree.put(acc.accounts, pubkey.value, account)
        }
      end)
    {:ok, new_chainstate}
  catch
    {:error, _} = err ->
      err
  end

  def update_offchain_chainstate(%Chainstate{}, _) do
    {:error, "#{__MODULE__}: The create update may only be aplied once"}
  end
end
