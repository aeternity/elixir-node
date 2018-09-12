defmodule Aeutil.Scientific do
  @moduledoc """
  Converts integer to scientific notation.
  It's used for storing the target in blocks and recalculating the next target
  """

  use Bitwise

  @highest_target_int 0xFFFF000000000000000000000000000000000000000000000000000000000000

  @spec scientific_to_integer(integer()) :: integer()
  def scientific_to_integer(scientific) do
    {exp, significand} = break_scientific(scientific)
    exp3 = exp - 3

    case exp >= 0 do
      true -> bsl(significand, 8 * exp3)
      false -> bsr(significand, -8 * exp3)
    end
  end

  @spec integer_to_scientific(integer()) :: integer()
  def integer_to_scientific(integer) do
    {exp, significand} = int_to_sci(integer, 3)

    case exp >= 0 do
      true -> bsl(exp, 24) + significand
      false -> bsl(-exp, 24) + 0x800000 + significand
    end
  end

  @spec compare_bin_to_significand(binary(), integer(), integer(), integer()) :: boolean()
  def compare_bin_to_significand(binary, significand, zeros, number_of_bits) do
    case binary do
      <<0::size(zeros), integer::size(number_of_bits), _rest::binary()>> ->
        integer < significand

      <<0::size(zeros), _rest::binary()>> ->
        :error

      _ ->
        false
    end
  end

  @spec break_scientific(integer()) :: tuple()
  def break_scientific(scientific) do
    significand_mask = bsl(1, 24) - 1

    exp =
      scientific
      |> bxor(significand_mask)
      |> bsr(24)

    significand = band(scientific, significand_mask)

    case band(0x800000, significand) do
      0 -> {exp, significand}
      _ -> {-exp, significand - 0x800000}
    end
  end

  # The Difficulty is calculated from the Target and is used in Sync.
  # Difficulty is used to select the winning fork of new blocks:
  # the difficulty of chain of blocks is the sum of the diffculty of each block.

  @spec target_to_difficulty(non_neg_integer()) :: float()
  def target_to_difficulty(target) do
    @highest_target_int / scientific_to_integer(target)
  end

  # Internal Functions

  @spec int_to_sci(integer(), integer()) :: tuple()
  defp int_to_sci(integer, exp) when integer > 0x7FFFFF do
    int_to_sci(bsr(integer, 8), exp + 1)
  end

  defp int_to_sci(integer, exp) when integer < 0x008000 do
    int_to_sci(bsl(integer, 8), exp - 1)
  end

  defp int_to_sci(integer, exp) do
    {exp, integer}
  end
end
