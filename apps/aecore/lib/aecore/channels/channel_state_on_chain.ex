defmodule Aecore.Channel.ChannelStateOnChain do
  @moduledoc """
  State Channel OnChain structure
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.Worker, as: Channel

  @type t :: %ChannelStateOnChain{
    initiator_pubkey: Wallet.pubkey(),
    responder_pubkey: Wallet.pubkey(),
    initiator_amount: integer(),
    responder_amount: integer(),
    lock_period: non_neg_integer(),
    closes_at: integer(),
    sequence: integer()
  }

  @type channels :: map() #TODO binary -> t()

  @doc """
  Definition of State Channel OnChain structure

  ## Parameters
  TODO
  """
  defstruct [
    :initiator_pubkey,
    :responder_pubkey,
    :initiator_amount,
    :responder_amount,
    :lock_period,
    :closes_at,
    :sequence
  ]

  use ExConstructor

  @spec create(Wallet.pubkey(), Wallet.pubkey(), integer(), integer(), non_neg_integer()) :: ChannelStateOnChain.t()
  def create(initiator_pubkey, responder_pubkey, initiator_amount, responder_amount, lock_period) do
    %ChannelStateOnChain{
      initiator_pubkey: initiator_pubkey,
      responder_pubkey: responder_pubkey,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount,
      lock_period: lock_period,
      closes_at: -1,
      sequence: -1
    }
  end

end
