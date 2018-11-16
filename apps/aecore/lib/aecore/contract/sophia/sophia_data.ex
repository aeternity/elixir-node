defmodule Aecore.Contract.Sophia.SophiaData do

  @word_size_bits 256

  def get_function_hash_from_call_data(call_data) do
    <<_::size(@word_size_bits), function_hash_int::size(@word_size_bits), _::binary>> = call_data

    <<function_hash_int::size(@word_size_bits)>>
  end

end
