defmodule AeutilScientificTest do
  use ExUnit.Case

  alias Aeutil.Scientific

  test "integer to scientific" do
    assert 0x01010000 == Scientific.integer_to_scientific(1)
    assert 0x0200FF00 == Scientific.integer_to_scientific(255)
    assert 0x02010000 == Scientific.integer_to_scientific(256)
    assert 0x02010100 == Scientific.integer_to_scientific(257)
  end

  test "scientific to integer" do
    assert 1 == Scientific.scientific_to_integer(0x01010000)
    assert 255 == Scientific.scientific_to_integer(0x0200FF00)
    assert 256 == Scientific.scientific_to_integer(0x02010000)
    assert 257 == Scientific.scientific_to_integer(0x02010100)
  end
end
