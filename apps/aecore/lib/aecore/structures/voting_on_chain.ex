defmodule Aecore.Structures.VotingOnChain do
  @moduledoc """
  Aecore structure of a transaction data.
  """
  alias Aecore.Structures.TxData
  alias Aecore.Structures.VotingOnChain
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.ChainState
  alias Aecore.Keys.Worker, as: Keys

  @type t :: %VotingOnChain{
    requester: binary(),
    comment: map(),
    start_height: integer(),
    end_height: integer(),
    formula: binary(),
    initial_state: map(),
    state: map(),
  }

  @doc """
  Definition of Voting structure

  ## Parameters 
  """
  defstruct [:requester, :comment, :start_height, :end_height, :formula, :initial_state, :state]
  use ExConstructor

  @single_choice "Voting.Formula.SingleChoice"
  @multi_choice "Voting.Formula.MultiChoice"

  @spec create(binary(), map(), integer(), integer(), binary(), map()) :: VotingOnChain.t()
  def create(requester, comment, start_height, end_height, formula, initial_state) do
    %VotingOnChain{requester: requester,
                   comment: comment,
                   start_height: start_height,
                   end_height: end_height,
                   formula: formula,
                   initial_state: initial_state,
                   state: initial_state}
  end

  @spec create_from_tx!(TxData.t(), integer()) :: VotingOnChain.t()
  def create_from_tx!(tx, block_height) do
    if tx.data.start_height < block_height do
      throw {:error, "start_height smaller then current height"}
    end
    if tx.data.end_height <= tx.data.start_height do
      throw {:error, "end_height isn't bigger then start_height"}
    end
    get_formula_fun!(tx.data.formula) #We check if formula fun exists
    if tx.value != 0 do
      throw {:error, "Question tx shouldn't contain tokens"}
    end
    create(tx.from_acc, tx.data.comment, tx.data.start_height, tx.data.end_height, tx.data.formula, tx.data.initial_state)
  end

  def create_question_tx(comment, start_height, end_height, formula, initial_state) do
    {:ok, pubkey} = Keys.pubkey()
    data = %{comment: comment,
             start_height: start_height,
             end_height: end_height,
             formula: formula,
             initial_state: initial_state}
    {:ok, tx} = TxData.create(pubkey, 
                              ChainState.addr_voting_on_chain_create,
                              0,
                              Chain.chain_state[pubkey].nonce + 1,
                              25,
                              0,
                              data)
    create_from_tx!(tx, Chain.top_height() + 1) #We check if voting can be created in next block
    tx
  end

  @spec tx_in!(VotingOnChain.t(), TxData.t(), integer()) :: VotingOnChain.t()
  def tx_in!(voting, tx, block_height) do
    if tx.value != 0 do
      throw {:error, "Vote tx shouldn't contain tokens"}
    end
    if block_height <= voting.start_height || block_height > voting.end_height do
      throw {:error, "Tx outside of timeframe"}
    end
    voter_at_start = Map.get(Chain.chain_state(), tx.from_acc) #FIXME: we should get the chainstate at start. This requires some important changes (access to prev_block hash in this function, access to n-th prev block by block hash)
    if voter_at_start == nil do
      throw {:error, "Voter didn't exist at VotingOnChain start"}
    end
    new_state = get_formula_fun!(voting.formula).(voting.state, tx.from_acc, voter_at_start, tx.data)
    %VotingOnChain{voting | state: new_state}
  end

  def get_hash(voting) do
    constant_fields = %{requester: voting.requester,
                        comment: voting.comment,
                        start_height: voting.start_height,
                        end_height: voting.end_height,
                        formula: voting.formula,
                        initial_state: voting.initial_state}
    voting_bin = :erlang.term_to_binary(constant_fields)
    :crypto.hash(:sha256, voting_bin)
  end

  defp get_formula_fun!(formula) do
    case formula do
      @single_choice ->
        &single_choice_formula/4
      @multi_choice ->
        &multi_choice_formula/4
      _ ->
        throw {:error, "Invalid formula"}
    end
  end
  
  defp single_choice_formula(state, voter_address, voter, data) do
    if Map.has_key?(state.voters, voter_address) do
      throw {:error, "Account already voted"}
    end
    new_voters = Map.put(state.voters, voter_address, true)
    if !Map.has_key?(state.results, data.choice) do
      throw {:error, "Unknown choice"}
    end
    new_results = Map.put(state.results, 
                          data.choice, 
                          Map.get(state.results, data.choice) + voter.balance)
    %{state | voters: new_voters, results: new_results}
  end

  defp multi_choice_formula(state, voter_address, voter, data) do
    if MapSet.has_key?(state.voters, voter_address) do
      throw {:error, "Account already voted"}
    end
    new_voters = Map.put(state.voters, voter_address, true)
    new_results = Enum.reduce(data.choices,
                              state.results,
                              fn(choice, results) ->
                                if !Map.has_key?(results, choice) do
                                  throw {:error, "Unknown choice"}
                                end
                                Map.put(results, 
                                        choice,
                                        Map.get(results, choice) + voter.balance)
                              end)
    %{state | voters: new_voters, results: new_results}
  end
end
