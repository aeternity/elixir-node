defmodule Aecore.Chain.PoF do
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.{MicroBlock, MicroHeader, KeyBlock, KeyHeader}

  require Logger

  @spec check_for_fraud(list(MicroBlock.t()), MicroHeader.t() | KeyHeader.t()) ::
          {MicroHeader.t(), MicroHeader.t(), binary()}
  def check_for_fraud(generation, %MicroHeader{prev_hash: new_prev_hash} = new_header) do
    sibling =
      Enum.find(generation, fn %MicroBlock{header: %MicroHeader{prev_hash: prev_hash}} ->
        prev_hash == new_prev_hash
      end)

    case sibling do
      nil ->
        :no_fraud

      %MicroBlock{header: %MicroHeader{prev_key_hash: prev_key_hash} = header} ->
        {:ok, %KeyBlock{header: %KeyHeader{miner: miner}}} = Chain.get_block(prev_key_hash)
        {header, new_header, miner}
    end
  end

  def check_for_fraud(_generation, %KeyHeader{}), do: :no_fraud
end
