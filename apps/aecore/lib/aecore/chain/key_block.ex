defmodule Aecore.Chain.KeyBlock do
  @moduledoc """
  Module defining the KeyBlock structure
  """
  alias Aecore.Chain.KeyBlock
  alias Aecore.Chain.KeyHeader

  @type t :: %KeyBlock{
          header: KeyHeader.t()
        }

  defstruct [:header]
end
