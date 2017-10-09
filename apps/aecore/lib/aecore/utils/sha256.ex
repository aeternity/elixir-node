defmodule Aecore.Utils.Sha256 do
  @moduledoc """
  TODO
  """
  @hash_bytes 32
  @hash_bits 256

  def hash(data) when is_binary(data) do
    <<hash :: size(@hash_bits), _ :: binary>> = :crypto.hash(:sha256, data)
    <<hash :: size(@hash_bits)>>
  end
  def hash(term)  do
    hash(:erlang.term_to_binary(term))
  end

  def binary_to_scientific(bin) do
    binary_to_scientific(bin, 0)
  end

  def binary_to_scientific(<<0 :: size(1), tail :: binary>>, zeros) do
    binary_to_scientific(tail, zeros + 1)
  end
  def binary_to_scientific(<<significand :: size(8), _tail :: binary>>, zeros) do
    ## We assume difficulty is encoded similarly
    256*(@hash_bits - zeros) + significand
  end

  def scientific_to_integer(s) do
    exp =  div(s,256)
    significand = rem(s,256)
    :erlang.bsl(significand, (exp - 7))
  end

  def integer_to_scientific(i) do
    exp = log2(i)
    256*exp + :erlang.bsr(i, (exp - 7))
  end

  ##------------------------------------------------------------------------------
  ## Base-2 integer logarithm
  ##------------------------------------------------------------------------------
  defp log2(1) do
    0
  end
  defp log2(n) when n > 1 do
    1 + log2(div(n,2))
  end

end
