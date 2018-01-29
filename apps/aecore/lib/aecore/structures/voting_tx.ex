defmodule Aecore.Structures.VotingTx do
  alias Aecore.Structures.VotingTx

  @type t :: %VotingTx{
    data: VotingQuestionTx.t() | VotingAnswerTx.t()
  }

  defstruct [:data]
  use ExConstructor

end
