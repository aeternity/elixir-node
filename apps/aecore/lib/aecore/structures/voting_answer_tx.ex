defmodule Aecore.Structures.VotingAnswerTx do
  alias Aecore.Structures.VotingAnswerTx

  @type t :: %VotingAnswerTx{
          hash_question: binary(),
          answer: list()
        }

  defstruct [:hash_question, :answer]
  use ExConstructor

  @spec create(binary(), list()) :: {:ok, VotingAnswerTx.t()}
  def create(hash_question, answer) do
    {:ok,
     %VotingAnswerTx{
       hash_question: hash_question,
       answer: answer
     }}
  end

  @spec hash_tx(VotingAnswerTx.t()) :: binary()
  def hash_tx(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
  end
end
