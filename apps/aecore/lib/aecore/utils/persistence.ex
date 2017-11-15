defmodule Aecore.Utils.Persistence do
  @moduledoc """
  Store/Restore latest blockchain and chainstate
  """

  @persistence_table Application.get_env(:aecore, :persistence)[:table]
  @blockchain_key :block_chain_state_key

  def store_state(state) do
    {:ok, table} = :dets.open_file(@persistence_table , [type: :set])
    :ok = :dets.insert(table, {@blockchain_key, state})
    halt_dets(table)
  end

  @spec get_block_chain_states() :: {:ok, term()}
  def get_block_chain_states() do
    {:ok, table} = :dets.open_file(@persistence_table , [type: :set])
    resp = case :dets.lookup(table, @blockchain_key) do
             [] -> {:ok, :nothing_to_restore}
             restored_data -> {:ok, Keyword.fetch!(restored_data, @blockchain_key)}
           end
    halt_dets(table)
    resp
  end

  defp halt_dets(table) do
    :dets.close(table)
    :dets.stop()
  end

end
