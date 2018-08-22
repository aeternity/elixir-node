defmodule PoiEpochCompabilityTest do

  use ExUnit.Case

  alias Aecore.Poi.Poi
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aeutil.Serialization
  alias Aecore.Chain.Chainstate

  test "Check if serialized POI from epoch containing two accounts is deserialized properly" do
    epoch_serialized_poi = <<249,1,131,60,1,249,1,121,249,1,118,160,216,55,139,150,160,144,59,133,171,70,176,146,127,153,173,68,12,149,144,174,32,147,116,50,207,241,190,134,8,59,197,217,249,1,82,248,72,160,38,96,171,194,141,80,120,246,179,21,48,76,92,54,104,95,29,221,38,237,27,115,189,87,79,173,136,28,253,55,69,85,230,159,32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,123,133,196,10,1,0,0,248,116,160,155,236,14,46,210,217,52,46,175,135,243,174,19,20,54,140,128,203,51,201,75,85,158,59,233,50,75,22,19,193,37,224,248,81,128,128,128,128,160,38,96,171,194,141,80,120,246,179,21,48,76,92,54,104,95,29,221,38,237,27,115,189,87,79,173,136,28,253,55,69,85,160,172,205,17,84,83,18,33,115,196,238,228,238,251,91,218,238,208,61,126,217,19,62,138,250,206,122,97,95,201,94,124,17,128,128,128,128,128,128,128,128,128,128,128,248,72,160,172,205,17,84,83,18,33,115,196,238,228,238,251,91,218,238,208,61,126,217,19,62,138,250,206,122,97,95,201,94,124,17,230,159,32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,124,133,196,10,1,0,0,248,70,160,216,55,139,150,160,144,59,133,171,70,176,146,127,153,173,68,12,149,144,174,32,147,116,50,207,241,190,134,8,59,197,217,228,130,17,35,160,155,236,14,46,210,217,52,46,175,135,243,174,19,20,54,140,128,203,51,201,75,85,158,59,233,50,75,22,19,193,37,224,192,192,192,192,192>>

  epoch_poi_hash = <<164,35,213,55,46,81,245,135,105,134,193,162,225,200,135,224,89,7,142,216,16,174,140,231,68,155,38,22,126,202,73,138>>

  epoch_account_pub_key1 = <<18,52,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,123>>
  epoch_account_pub_key2 = <<18,53,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,124>>

  poi = Serialization.rlp_decode_anything(epoch_serialized_poi)
  assert %Poi{} = poi

  assert Serialization.rlp_encode(poi) === epoch_serialized_poi
  assert Poi.calculate_root_hash(poi) === epoch_poi_hash

  account1 = Account.new(%{balance: 0, nonce: 0, pubkey: epoch_account_pub_key1})
  account2 = Account.new(%{balance: 0, nonce: 0, pubkey: epoch_account_pub_key2})

  #test verification
  assert true === Poi.verify_poi(poi, epoch_account_pub_key1, account1)
  assert true === Poi.verify_poi(poi, epoch_account_pub_key2, account2)

  #test verification of invalid accounts
  assert false === Poi.verify_poi(poi, epoch_account_pub_key1, %Account{account1 | balance: 2})
  assert false === Poi.verify_poi(poi, epoch_account_pub_key2, %Account{account2 | balance: 2})

  #test lookups
  {:ok, account_lookup1} = Poi.lookup_poi(:accounts, poi, epoch_account_pub_key1)
  {:ok, account_lookup2} = Poi.lookup_poi(:accounts, poi, epoch_account_pub_key2)
  assert_accounts_equal(account1, account_lookup1)
  assert_accounts_equal(account2, account_lookup2)

  #construct a poi from scratch and check if the serialization is compatible with epoch
  chainstate = Chainstate.create_chainstate_trees()
  updated_accounts =
    chainstate.accounts
    |> AccountStateTree.put(epoch_account_pub_key1, account1)
    |> AccountStateTree.put(epoch_account_pub_key2, account2)
  chainstate = %Chainstate{chainstate | accounts: updated_accounts}

  assert epoch_poi_hash === Chainstate.calculate_root_hash(chainstate)

  poi = Poi.construct(chainstate)
  assert epoch_poi_hash === Poi.calculate_root_hash(poi)
  assert {:error, :key_not_present} === Poi.lookup_poi(:accounts, poi, epoch_account_pub_key1)
  assert {:error, :key_not_present} === Poi.lookup_poi(:accounts, poi, epoch_account_pub_key2)

  {:ok, poi} = Poi.add_to_poi(:accounts, epoch_account_pub_key1, chainstate, poi)
  assert epoch_poi_hash === Poi.calculate_root_hash(poi)
  assert {:ok, _} = Poi.lookup_poi(:accounts, poi, epoch_account_pub_key1)
  assert {:error, :key_not_present} === Poi.lookup_poi(:accounts, poi, epoch_account_pub_key2)

  {:ok, poi} = Poi.add_to_poi(:accounts, epoch_account_pub_key2, chainstate, poi)
  assert epoch_poi_hash === Poi.calculate_root_hash(poi)
  assert {:ok, _} = Poi.lookup_poi(:accounts, poi, epoch_account_pub_key1)
  assert {:ok, _} = Poi.lookup_poi(:accounts, poi, epoch_account_pub_key2)

  assert Serialization.rlp_encode(poi) === epoch_serialized_poi
  end

  defp assert_accounts_equal(
         %Account{balance: balance1, nonce: nonce1},
         %Account{balance: balance2, nonce: nonce2}) do
    assert balance1 === balance2
    assert nonce1 === nonce2
  end

end


