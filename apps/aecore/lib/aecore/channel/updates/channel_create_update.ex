defmodule Aecore.Channel.Updates.ChannelCreateUpdate do

  alias Aecore.Channel.Updates.ChannelCreateUpdate
  alias Aecore.Channel.ChannelOffchainUpdate
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Identifier
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account
  alias Aecore.Channel.Tx.ChannelCreateTx

  @behaviour ChannelOffchainUpdate

  @type t :: %ChannelCreateUpdate{
          initiator: Identifier.t(),
          initiator_amount: non_neg_integer(),
          responder: Identifier.t(),
          responder_amount: non_neg_integer()
        }

  defstruct [:initiator, :initiator_amount, :responder, :responder_amount]

  def new(%ChannelCreateTx{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
      responder_amount: responder_amount})
  do
    %ChannelCreateUpdate{
      initiator: initiator,
      initiator_amount: initiator_amount,
      responder: responder,
      responder_amount: responder_amount
    }
  end

  def decode_from_list(_)
  do
    {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  def encode_to_list(_)
  do
    {:error, "#{__MODULE__}: ChannelCreateUpdate MUST not be included in ChannelOffchainTx"}
  end

  @doc """
    Creates the initial chainstate. Assumes no chainstate is present.
  """
  def update_offchain_chainstate(nil,
        %ChannelCreateUpdate{
          initiator: initiator,
          initiator_amount: initiator_amount,
          responder: responder,
          responder_amount: responder_amount
        },
        minimal_deposit)
  do
    Enum.reduce(
      [
        {initiator, initiator_amount},
        {responder, responder_amount}
      ],
      Chainstate.create_chainstate_trees(),
      fn {pubkey, amount}, acc ->
        account =
          Account.new(%{balance: amount, nonce: 0, pubkey: pubkey})
          |> ChannelOffchainUpdate.ensure_minimal_deposit_is_meet!(minimal_deposit)
        %Chainstate{
          acc
          | accounts: AccountStateTree.put(acc.accounts, pubkey, account)
        }
      end)
  end

  def update_offchain_chainstate(%Chainstate{}, _) do
    {:error, "#{__MODULE__}: The create update may only be aplied once"}
  end
end
