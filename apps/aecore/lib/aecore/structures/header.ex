defmodule Aecore.Structures.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Structures.Header

  defstruct [:height,
            :prev_hash,
            :txs_hash,
            :difficulty_target,
            :nonce,
            :timestamp,
            :version]
  use ExConstructor

  @type header() :: %Header{}

  def create do
    Header.new(%{})
  end
end
