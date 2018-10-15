defmodule PoiEpochCompabilityTest do
  @moduledoc """
    Functional tests and tests for checking if Poi's are compatible with Epoch.
  """

  use ExUnit.Case

  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Poi.Poi
  alias Aecore.Chain.Chainstate
  alias Aeutil.Serialization

  @typedoc """
  Type specifying a list of accounts together with their pubkeys
  """
  @type account_list :: list({Keys.pubkey(), Account.t()})

  @typedoc """
  Type of the state hash
  """
  @type state_hash :: binary()

  @epoch_account_pub_key1 <<18, 52, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 123>>
  @epoch_account_pub_key2 <<18, 53, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 124>>
  @epoch_account_pub_key3 <<19, 69, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 125>>
  @epoch_account_pub_key4 <<19, 70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 126>>

  @account1 Account.new(%{balance: 0, nonce: 0, pubkey: @epoch_account_pub_key1})
  @account2 Account.new(%{balance: 0, nonce: 0, pubkey: @epoch_account_pub_key2})
  @account3 Account.new(%{balance: 0, nonce: 0, pubkey: @epoch_account_pub_key1})
  @account4 Account.new(%{balance: 0, nonce: 0, pubkey: @epoch_account_pub_key2})

  test "Poi containing two accounts created from chainstate containing four accounts" do
    epoch_serialized_poi =
      <<249, 2, 61, 60, 1, 249, 2, 51, 249, 2, 48, 160, 122, 252, 130, 11, 225, 228, 88, 182, 240,
        77, 9, 83, 182, 186, 84, 37, 42, 95, 33, 167, 234, 223, 190, 136, 26, 35, 126, 145, 124,
        205, 229, 62, 249, 2, 12, 248, 68, 160, 23, 55, 70, 52, 145, 79, 122, 71, 25, 250, 200,
        23, 159, 142, 217, 214, 198, 89, 120, 152, 157, 71, 14, 82, 124, 173, 55, 163, 238, 20,
        226, 149, 226, 19, 160, 155, 236, 14, 46, 210, 217, 52, 46, 175, 135, 243, 174, 19, 20,
        54, 140, 128, 203, 51, 201, 75, 85, 158, 59, 233, 50, 75, 22, 19, 193, 37, 224, 248, 72,
        160, 38, 96, 171, 194, 141, 80, 120, 246, 179, 21, 48, 76, 92, 54, 104, 95, 29, 221, 38,
        237, 27, 115, 189, 87, 79, 173, 136, 28, 253, 55, 69, 85, 230, 159, 32, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 123, 133, 196, 10, 1,
        0, 0, 248, 68, 160, 122, 252, 130, 11, 225, 228, 88, 182, 240, 77, 9, 83, 182, 186, 84,
        37, 42, 95, 33, 167, 234, 223, 190, 136, 26, 35, 126, 145, 124, 205, 229, 62, 226, 17,
        160, 140, 136, 193, 67, 180, 193, 212, 7, 241, 173, 255, 54, 137, 8, 123, 79, 219, 113,
        43, 140, 233, 116, 138, 212, 211, 202, 187, 72, 38, 182, 65, 61, 248, 116, 160, 140, 136,
        193, 67, 180, 193, 212, 7, 241, 173, 255, 54, 137, 8, 123, 79, 219, 113, 43, 140, 233,
        116, 138, 212, 211, 202, 187, 72, 38, 182, 65, 61, 248, 81, 128, 128, 160, 23, 55, 70, 52,
        145, 79, 122, 71, 25, 250, 200, 23, 159, 142, 217, 214, 198, 89, 120, 152, 157, 71, 14,
        82, 124, 173, 55, 163, 238, 20, 226, 149, 160, 156, 70, 131, 238, 40, 163, 38, 171, 241,
        7, 241, 90, 234, 201, 245, 43, 15, 103, 221, 108, 98, 122, 232, 143, 74, 128, 84, 39, 150,
        255, 251, 10, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 248, 116,
        160, 155, 236, 14, 46, 210, 217, 52, 46, 175, 135, 243, 174, 19, 20, 54, 140, 128, 203,
        51, 201, 75, 85, 158, 59, 233, 50, 75, 22, 19, 193, 37, 224, 248, 81, 128, 128, 128, 128,
        160, 38, 96, 171, 194, 141, 80, 120, 246, 179, 21, 48, 76, 92, 54, 104, 95, 29, 221, 38,
        237, 27, 115, 189, 87, 79, 173, 136, 28, 253, 55, 69, 85, 160, 172, 205, 17, 84, 83, 18,
        33, 115, 196, 238, 228, 238, 251, 91, 218, 238, 208, 61, 126, 217, 19, 62, 138, 250, 206,
        122, 97, 95, 201, 94, 124, 17, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 248,
        72, 160, 172, 205, 17, 84, 83, 18, 33, 115, 196, 238, 228, 238, 251, 91, 218, 238, 208,
        61, 126, 217, 19, 62, 138, 250, 206, 122, 97, 95, 201, 94, 124, 17, 230, 159, 32, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 124, 133,
        196, 10, 1, 0, 0, 192, 192, 192, 192, 192>>

    epoch_poi_hash =
      <<96, 96, 171, 230, 79, 84, 162, 143, 216, 173, 145, 147, 26, 17, 213, 15, 168, 73, 223,
        138, 0, 31, 23, 205, 165, 147, 154, 187, 200, 198, 62, 5>>

    do_test(
      epoch_serialized_poi,
      epoch_poi_hash,
      [
        {@epoch_account_pub_key1, @account1},
        {@epoch_account_pub_key2, @account2}
      ],
      [
        {@epoch_account_pub_key3, @account3},
        {@epoch_account_pub_key4, @account4}
      ]
    )
  end

  test "Poi containing two accounts" do
    epoch_serialized_poi =
      <<249, 1, 131, 60, 1, 249, 1, 121, 249, 1, 118, 160, 216, 55, 139, 150, 160, 144, 59, 133,
        171, 70, 176, 146, 127, 153, 173, 68, 12, 149, 144, 174, 32, 147, 116, 50, 207, 241, 190,
        134, 8, 59, 197, 217, 249, 1, 82, 248, 72, 160, 38, 96, 171, 194, 141, 80, 120, 246, 179,
        21, 48, 76, 92, 54, 104, 95, 29, 221, 38, 237, 27, 115, 189, 87, 79, 173, 136, 28, 253,
        55, 69, 85, 230, 159, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 123, 133, 196, 10, 1, 0, 0, 248, 116, 160, 155, 236, 14, 46, 210,
        217, 52, 46, 175, 135, 243, 174, 19, 20, 54, 140, 128, 203, 51, 201, 75, 85, 158, 59, 233,
        50, 75, 22, 19, 193, 37, 224, 248, 81, 128, 128, 128, 128, 160, 38, 96, 171, 194, 141, 80,
        120, 246, 179, 21, 48, 76, 92, 54, 104, 95, 29, 221, 38, 237, 27, 115, 189, 87, 79, 173,
        136, 28, 253, 55, 69, 85, 160, 172, 205, 17, 84, 83, 18, 33, 115, 196, 238, 228, 238, 251,
        91, 218, 238, 208, 61, 126, 217, 19, 62, 138, 250, 206, 122, 97, 95, 201, 94, 124, 17,
        128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 248, 72, 160, 172, 205, 17, 84, 83,
        18, 33, 115, 196, 238, 228, 238, 251, 91, 218, 238, 208, 61, 126, 217, 19, 62, 138, 250,
        206, 122, 97, 95, 201, 94, 124, 17, 230, 159, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 124, 133, 196, 10, 1, 0, 0, 248, 70, 160,
        216, 55, 139, 150, 160, 144, 59, 133, 171, 70, 176, 146, 127, 153, 173, 68, 12, 149, 144,
        174, 32, 147, 116, 50, 207, 241, 190, 134, 8, 59, 197, 217, 228, 130, 17, 35, 160, 155,
        236, 14, 46, 210, 217, 52, 46, 175, 135, 243, 174, 19, 20, 54, 140, 128, 203, 51, 201, 75,
        85, 158, 59, 233, 50, 75, 22, 19, 193, 37, 224, 192, 192, 192, 192, 192>>

    epoch_poi_hash =
      <<164, 35, 213, 55, 46, 81, 245, 135, 105, 134, 193, 162, 225, 200, 135, 224, 89, 7, 142,
        216, 16, 174, 140, 231, 68, 155, 38, 22, 126, 202, 73, 138>>

    do_test(
      epoch_serialized_poi,
      epoch_poi_hash,
      [
        {@epoch_account_pub_key1, @account1},
        {@epoch_account_pub_key2, @account2}
      ],
      []
    )
  end

  test "Empty Poi created from an chainstate containing two entries" do
    epoch_serialized_poi =
      <<235, 60, 1, 227, 226, 160, 216, 55, 139, 150, 160, 144, 59, 133, 171, 70, 176, 146, 127,
        153, 173, 68, 12, 149, 144, 174, 32, 147, 116, 50, 207, 241, 190, 134, 8, 59, 197, 217,
        192, 192, 192, 192, 192, 192>>

    epoch_poi_hash =
      <<164, 35, 213, 55, 46, 81, 245, 135, 105, 134, 193, 162, 225, 200, 135, 224, 89, 7, 142,
        216, 16, 174, 140, 231, 68, 155, 38, 22, 126, 202, 73, 138>>

    do_test(epoch_serialized_poi, epoch_poi_hash, [], [
      {@epoch_account_pub_key1, @account1},
      {@epoch_account_pub_key2, @account2}
    ])
  end

  test "POI for empty chainstate" do
    epoch_serialized_poi = <<200, 60, 1, 192, 192, 192, 192, 192, 192>>

    epoch_poi_hash =
      <<49, 99, 216, 27, 4, 197, 48, 200, 107, 41, 191, 230, 2, 119, 201, 74, 161, 17, 210, 121,
        137, 166, 44, 160, 121, 137, 123, 240, 229, 129, 49, 206>>

    do_test(epoch_serialized_poi, epoch_poi_hash, [], [])
  end

  @spec do_test(binary(), state_hash(), account_list(), account_list()) :: no_return
  defp do_test(epoch_serialized_poi, epoch_poi_hash, included_accounts, excluded_accounts) do
    deserialized_poi = deserialize_poi(epoch_serialized_poi, epoch_poi_hash)

    test_poi(deserialized_poi, included_accounts, excluded_accounts)

    # construct a poi from scratch and check if the serialization is compatible with epoch
    chainstate =
      create_chainstate_with_accounts(included_accounts ++ excluded_accounts, epoch_poi_hash)

    constructed_poi = build_poi(chainstate, epoch_poi_hash, included_accounts, excluded_accounts)

    assert epoch_serialized_poi === Serialization.rlp_encode(constructed_poi)
  end

  # Creates a chainstate from a list of accounts and checks if the root hash matches
  @spec create_chainstate_with_accounts(account_list(), state_hash()) :: Chainstate.t()
  defp create_chainstate_with_accounts(accounts, root_hash) do
    chainstate = Chainstate.create_chainstate_trees()

    updated_accounts =
      Enum.reduce(accounts, chainstate.accounts, fn {pub_key, account}, acc ->
        AccountStateTree.put(acc, pub_key, account)
      end)

    updated_chainstate = %Chainstate{chainstate | accounts: updated_accounts}
    assert root_hash === Chainstate.calculate_root_hash(updated_chainstate)
    updated_chainstate
  end

  # Deserializes Poi and does basic serialization tests
  @spec deserialize_poi(binary(), state_hash()) :: Poi.t()
  defp deserialize_poi(serialized_poi, root_hash) do
    {:ok, %Poi{} = poi} = Serialization.rlp_decode_only(serialized_poi, Poi)

    assert Serialization.rlp_encode(poi) === serialized_poi
    assert Poi.calculate_root_hash(poi) === root_hash

    poi
  end

  # Creates a Poi from a chainstate and tests whether it functions as expected
  @spec build_poi(Chainstate.t(), state_hash(), account_list(), account_list()) :: Poi.t()
  defp build_poi(chainstate, root_hash, included_accounts, excluded_accounts) do
    poi = Poi.construct(chainstate)
    assert root_hash === Poi.calculate_root_hash(poi)

    # In the begining there are no accounts in the Poi
    test_poi(poi, [], included_accounts ++ excluded_accounts)

    # Add accounts to the Poi one by one and test if they are properly included in the Poi
    {constructed_poi, _, _} =
      Enum.reduce(
        included_accounts,
        {poi, [], included_accounts ++ excluded_accounts},
        fn {pub_key, _}, {acc, included, [account | excluded]} ->
          # Add the account to the Poi
          {:ok, new_acc} = Poi.add_to_poi(:accounts, pub_key, chainstate, acc)
          assert root_hash === Poi.calculate_root_hash(new_acc)

          # Test if it was properly included
          new_included = [account] ++ included
          test_poi(new_acc, new_included, excluded)
          {new_acc, new_included, excluded}
        end
      )

    constructed_poi
  end

  # Some basic functional tests on Poi
  @spec test_poi(Poi.t(), account_list(), account_list()) :: no_return
  defp test_poi(poi, included_accounts, excluded_accounts) do
    Enum.each(included_accounts, fn {pub_key, account} ->
      # test verification
      assert true === Poi.verify_poi?(poi, pub_key, account)

      # test verification of invalid accounts
      assert false ===
               Poi.verify_poi?(poi, pub_key, %Account{account | balance: account.balance + 1})

      # test lookups
      {:ok, account_lookup} = Poi.lookup_poi(:accounts, poi, pub_key)
      assert_accounts_equal(account, account_lookup)
    end)

    Enum.each(excluded_accounts, fn {pub_key, account} ->
      # test verification fails
      assert false === Poi.verify_poi?(poi, pub_key, account)

      # test lookups
      {:error, :key_not_present} = Poi.lookup_poi(:accounts, poi, pub_key)
    end)
  end

  @spec assert_accounts_equal(Account.t(), Account.t()) :: no_return
  defp assert_accounts_equal(%Account{balance: balance1, nonce: nonce1}, %Account{
         balance: balance2,
         nonce: nonce2
       }) do
    assert balance1 === balance2
    assert nonce1 === nonce2
  end
end
