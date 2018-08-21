defmodule Aecore.POI do

  alias Aecore.POI

  defstruct [
    :accounts,
    :calls,
    :channels,
    :contracts,
    :ns,
    :oracles
  ]

  use ExConstructor
  use Aecore.Util.Serializable



  def serialize() do end

end
