defmodule Aecore.Chain.KeyBlock do
  alias Aecore.Chain.KeyBlock
  alias Aecore.Chain.KeyHeader

  @type t :: %KeyBlock{
          header: KeyHeader
        }

  defstruct [:header]
end
