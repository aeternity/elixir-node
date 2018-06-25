defmodule AevmConst do
  @moduledoc """
    Module for defining macros for general util
  """

  # credo:disable-for-this-file

  require Bitwise

  defmacro mask256 do quote do: Bitwise.bsl(1, 256) - 1 end
  defmacro neg2to255 do quote do: (-Bitwise.band(Bitwise.bsl(1, 256), AevmConst.mask256)) end

end
