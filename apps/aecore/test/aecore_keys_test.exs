defmodule AecoreKeysTest do
  @moduledoc """
  Unit tests for the keys module
  """

  use ExUnit.Case
  doctest Aecore.Keys.Worker

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Keys.start_link([])
    []
  end

  test "test if a pubkey is loaded" do
    assert {:ok, _key} = Keys.pubkey()
  end

  test "sign transaction" do
    {:ok, to_account} = Keys.pubkey()
    assert {:ok, _} = Keys.sign_tx(to_account, 5,
                                   Map.get(Chain.chain_state,
                                           to_account, %{nonce: 0}).nonce + 1, 1,
                                   Chain.top_block().header.height +
                                    Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1)
  end

  test "check pubkey length" do
    pub_key_str = "041A470AE9831B61D9951A10D49663419CE087DF1BD7DB06578971767F032D389CB283AD4DD4E3532F3A5F3C89B006092CB6CECE39CAC3B06C2CB6DF8B51C73675"
    pub_key_bin = pub_key_str |> Base.decode16!()
    assert false  == Keys.verify("", "", pub_key_bin)
  end

  test "wrong key verification" do
    pub_key_str = "041A470AE9831B61D9951A10D49663419CE087DF1BD7DB06578971767F032D389CB283AD4DD4E3"
    pub_key_bin = pub_key_str |> Base.decode16!()

    assert {:error, _} = Keys.verify("", "", pub_key_bin)
  end

end
