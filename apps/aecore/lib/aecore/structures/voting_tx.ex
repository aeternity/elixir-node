defmodule Aecore.Structures.VotingTx do
  alias Aecore.Structures.VotingTx

  @type t :: %VotingTx{
    voting_payload: VotingQuestionTx.t() | VotingAnswerTx.t()
  }

  defstruct [:voting_payload]
  use ExConstructor

end
