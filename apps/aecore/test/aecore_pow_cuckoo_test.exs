defmodule AecoreCuckooTest do
  use ExUnit.Case, async: false

  alias Aecore.Pow.Cuckoo

  @highest_bitcoin_target_sci 486604799
  @highest_bitcoin_target_int 26959535291011309493156476344723991336010898738574164086137773096960
  @highest_target_sci 553713663
  @highest_target_int 115792082335569848633007197573932045576244532214531591869071028845388905840640

  @doctest Cuckoo

  @moduledoc """
  Unit tests for the cuckoo module
  """
  @tag timeout: 1000000000
  test "Generate with a winning nonce and high target threshold, verify it" do
    {t1, res}  =
      :timer.tc(Cuckoo, :generate,
        [<<"wsffgujnjkqhduihsahswgdf">>, @highest_target_sci, 100])
    IO.inspect "Generated in #{t1} microsecs"
    assert :ok =  :erlang.element(1, res)

    ## verify the beast
    {:ok, {nonce, soln}} = res
    {t2, res2} =
      :timer.tc(Cuckoo, :verify,
        [<<"wsffgujnjkqhduihsahswgdf">>, nonce, soln, @highest_target_sci])
    IO.inspect "Verified in #{t2} microsecs"
    ## if still does not working the verifing
    assert true = res2
  end

  test "Fail if retry count is zero" do
    assert {:error, :generation_count_exhausted} = Cuckoo.generate("", 5555, 0)
  end

  @tag timeout: 1000000000
  test "Generate with a winning nonce but low difficulty, shall fail" do
    ##Unlikely to succeed after 2 steps
    res = Cuckoo.generate(<<"wsffgujnjkqhduihsahswgdf">>, 16842752, 2)
    assert {:error, :generation_count_exhausted} = res
  end

end
