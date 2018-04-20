defmodule AevmTest do
  use ExUnit.Case
  doctest Aevm

  # test case from aevm core
  test "aevm test" do
    state =
      Aevm.loop(
        State.init_vm(
          %{
            :code =>
              "600035807f0000000000000000000000000000000000000000000000000000000000000000147f000000000000000000000000000000000000000000000000000000000000004957005b60203558602701907f000000000000000000000000000000000000000000000000000000000000007d565b60005260206000f35b9056",
            :address => 0,
            :caller => 0,
            :data => <<0::256, 42::256>>,
            :gas => 100_000,
            :gasPrice => 1,
            :origin => 0,
            :value => 0
          },
          %{:currentCoinbase => 0, :currentDifficulty => 0, :currentGasLimit => 10000, :currentNumber => 0, :currentTimestamp => 0},
          %{}
        )
      )

    assert state = %{
             address: 0,
             caller: 0,
             code:
               <<96, 0, 53, 128, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 73, 87, 0, 91, 96, 32,
                 53, 88, 96, 39, 1, 144, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 125, 86, 91, 96, 0, 82, 96, 32, 96, 0,
                 243, 91, 144, 86>>,
             currentCoinbase: 0,
             cp: 129,
             data:
               <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 42>>,
             currentDifficulty: 0,
             gas: 99915,
             currentGasLimit: 10000,
             gasPrice: 1,
             jumpdests: '}tI',
             logs: [],
             memory: %{0 => 42, :size => 1},
             currentNumber: 0,
             origin: 0,
             return:
               <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 42>>,
             stack: [0],
             storage: %{},
             currentTimestamp: 0,
             value: 0
           }
  end
end
