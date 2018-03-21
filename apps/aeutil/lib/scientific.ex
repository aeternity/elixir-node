defmodule Aeutil.Scientific do

  use Bitwise

  @highest_target_scientific 0x2100ffff
  @highest_target_integer 0xffff000000000000000000000000000000000000000000000000000000000000
  @nonce_bits 64
  @max_nonce 0xffffffffffffffff
  @nonce_range 1000000000000000000000000

  def scientific_to_integer(scientific) do
    {exp, significand} = break_scientific(scientific)
    exp3 = exp - 3
    case exp >= 0 do
      true -> bsl(significand, (8 * exp3))
      false -> bsr(significand, (-8 * exp3))
    end
  end

  def integer_to_scientific(integer) do
    {exp, significand} = int_to_sci(integer, 3)
    case exp >= 0 do
      true -> bsl(exp, 24) + significand
      false -> bsl(-exp, 24) + 0x800000 + significand
    end
  end



  defp int_to_sci(integer, exp) when integer > 0x7fffff do
     int_to_sci(bsr(integer, 8), exp + 1)
  end
  defp int_to_sci(integer, exp) when integer < 0x008000 do
    int_to_sci(bsl(integer, 8), exp - 1)
  end
  defp int_to_sci(integer, exp) do
    {exp, integer}
  end

  defp break_scientific(scientific) do
    significand_mask = bsl(1, 24) -1
    exp =
      bxor(scientific, significand_mask)
      |> bsr(24)
    significand = band(scientific, significand_mask)
    case band(0x800000, significand) do
      0 -> {exp, significand}
      _ -> {exp, significand - 0x800000}
    end
  end
end
