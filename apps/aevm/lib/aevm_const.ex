defmodule AevmConst do
  require Bitwise

  defmacro mask256 do quote do: Bitwise.bsl(1, 256) - 1 end
  defmacro neg2to255 do quote do: (-Bitwise.band(Bitwise.bsl(1, 256), AevmConst.mask256)) end

end
