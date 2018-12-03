defmodule Aecore.Chain.PoF do
  alias Aecore.Chain.PoF
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.{MicroBlock, MicroHeader, KeyBlock, KeyHeader}

  require Logger

  @type t :: %PoF{header1: MicroHeader.t(), header2: MicroHeader.t(), miner: binary()}

  defstruct([:header1, :header2, :miner])

  @spec check_for_fraud(list(MicroBlock.t()), MicroHeader.t() | KeyHeader.t()) ::
          {MicroHeader.t(), MicroHeader.t(), binary()}
  def check_for_fraud(
        generation_prev_hashes,
        %MicroHeader{prev_hash: new_prev_hash, prev_key_hash: prev_key_hash} = new_header
      ) do
    case generation_prev_hashes[new_prev_hash] do
      nil ->
        :no_fraud

      sibling_hash ->
        %MicroBlock{header: %MicroHeader{} = sibling_header} = Chain.get_block(sibling_hash)
        %KeyBlock{header: %KeyHeader{miner: miner}} = Chain.get_block(prev_key_hash)
        %PoF{header1: new_header, header2: sibling_header, miner: miner}
    end
  end

  def check_for_fraud(_generation_prev_hashes, %KeyHeader{}), do: :no_fraud
end
