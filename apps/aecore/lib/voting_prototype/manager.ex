defmodule Aecore.VotingPrototype.Manager do

  require Logger

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.VotingQuestionTx
  alias Aecore.Structures.VotingAnswerTx
  alias Aecore.Structures.VotingTx
  alias Aecore.Structures.SignedTx

  def register_question(%{} = tx_data) do
    process(VotingQuestionTx, tx_data)
  end

  def register_answer(%{} = tx_data) do
    process(VotingAnswerTx, tx_data)
  end

  def register({:question, tx_data}) do
    process(VotingQuestionTx, tx_data)
  end

  def register({:answer, tx_data}) do
    process(VotingAnswerTx, tx_data)
  end

  def register(_) do
    Logger.error("[Voting Manager] Registration failed, unknown input data")
    {:error, "unknown input data type"}
  end

  defp process(tx_type, tx_data) do
    {:ok, voting_tx} = build_struct(tx_type, tx_data)
    {:ok, signed_tx} = sign_tx(voting_tx)
    Pool.add_transaction(signed_tx)
  end

  def build_struct(structure, data) do
    try do
      {:ok, %VotingTx{voting_payload: struct!(structure, data)}}
    rescue
      error ->
        Logger.error(error)
      {:error, "bad map"}
    end
  end

  defp sign_tx(tx_data) do
    {:ok, signature} = Keys.sign(tx_data)
    {:ok, %SignedTx{data: tx_data, signature: signature}}
  end

  @spec hash_question(VotingQuestionTx.t()) :: binary()
  def hash_question(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
  end

end
