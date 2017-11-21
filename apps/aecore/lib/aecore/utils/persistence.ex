defmodule Aecore.Utils.Persistence do
  @moduledoc """
  Store/Restore latest blockchain and chainstate
  """

  @blockchain_key :block_chain_state_key

  @spec store_state(state :: tuple()) :: :ok
  def store_state(state) do
    {:ok, table} = :dets.open_file(persistence_table_path() , [type: :set])
    :ok = :dets.insert(table, {@blockchain_key, state})
    :ok = halt_dets(table)
  end

  @spec get_block_chain_states() :: {:ok, term()}
  def get_block_chain_states() do
    {:ok, table} = :dets.open_file(persistence_table_path() , [type: :set])
    resp = case :dets.lookup(table, @blockchain_key) do
             [] -> {:ok, :nothing_to_restore}
             restored_data -> {:ok, Keyword.fetch!(restored_data, @blockchain_key)}
           end
    :ok = halt_dets(table)
    resp
  end

  defp halt_dets(table) do
    :ok = :dets.close(table)
    :stopped = :dets.stop()
    :ok
  end

  defp persistence_table_path() do
    Application.get_env(:aecore, :persistence)[:table]
  end

end
