defmodule TestUtils do
  @moduledoc """
  Helper module for retrieving the chainstate
  """

  alias Aecore.Chain.Worker, as: Chain

  def get_accounts_chainstate do
    Chain.chain_state().accounts
  end
end
