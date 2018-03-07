defmodule Aecore.Structures.VotingTx do
  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.VotingQuestionTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Chain.Worker, as: Chain

  @type t :: %VotingTx{
          from_acc: binary(),
          fee: non_neg_integer(),
          nonce: non_neg_integer(),
          voting_payload: VotingQuestionTx.t() | VotingAnswerTx.t()
        }

  defstruct [
    :from_acc,
    :fee,
    :nonce,
    :voting_payload
  ]

  use ExConstructor

  @spec create(binary(), non_neg_integer(), VotingQuestionTx.t() | VotingAnswerTx.t()) ::
          {:ok, VotingTx.t()}
  def create(from_acc, fee, voting_payload) do
    {:ok,
     %VotingTx{
       from_acc: from_acc,
       fee: fee,
       nonce: Chain.lowest_valid_nonce(),
       voting_payload: voting_payload
     }}
  end
end
