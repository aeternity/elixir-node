defmodule Aecore.Structures.VotingAnswerTx do
  alias Aecore.Structures.VotingAnswerTx

  @type t :: %VotingAnswerTx{
    hash_question: binary(),
    answer: list(),
    from_acc: binary(),
    fee: non_neg_integer()
  }

  defstruct [:hash_question, :answer, :from_acc, :fee]
  use ExConstructor

  @spec create(binary(), list(), binary(), non_neg_integer()) :: {:ok, %VotingAnswerTx{}}
  def create(hash_question, answer, from_acc, fee) do
    {:ok, %VotingAnswerTx{hash_question: hash_question,
                          answer: answer,
                          from_acc: from_acc,
                          fee: fee}}
  end

  @spec hash_tx(VotingAnswerTx.t()) :: binary()
  def hash_tx(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
  end
end
