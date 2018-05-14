defmodule AecoreSerializationTest do
  use ExUnit.Case

  @moduledoc """
  Unit test for RLP data serialization/deserialization
  """
  alias Aecore.Chain.Header
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Oracle.Oracle
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Block
  alias Aecore.Naming.Naming
  alias Aecore.Account.AccountStateTree

  setup do
    Code.require_file("test_utils.ex", "./test")

    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      Pool.get_and_empty_pool()
      :ok
    end)
  end

  @tag :rlp_test
  test "SignedTx with DataTx inside serialization", setup do
    Miner.mine_sync_block_to_chain()
    signedtx = create_data(SignedTx)

    deserialized_signedtx =
      signedtx
      |> SignedTx.rlp_encode()
      |> SignedTx.rlp_decode()

    assert deserialized_signedtx = signedtx
  end

  @tag :rlp_test
  test "DataTx(SpendTx) serialization", setup do
    Miner.mine_sync_block_to_chain()
    spendtx = create_data(SpendTx)

    deserialized_spendtx =
      spendtx
      |> DataTx.rlp_encode()
      |> DataTx.rlp_decode()

    assert deserialized_spendtx = spendtx
  end
  @tag :rlp_test
  test "DataTx(CoinbaseTx) serialization", setup do
    Miner.mine_sync_block_to_chain()
    coinbasetx = create_data(CoinbaseTx).data
    serialized_coinbasetx = DataTx.rlp_encode(coinbasetx)
    deserialized_spendtx = DataTx.rlp_decode(serialized_coinbasetx)
    assert deserialized_spendtx == coinbasetx
  end

  @tag :rlp_test
  test "Account chain-state serialization" do
    {account, pkey} = create_data(Account)
    serialized_acc_info = Chainstate.rlp_encode(account, pkey)
    deserialized_acc_info = Chainstate.rlp_decode(serialized_acc_info)
    assert account_state = deserialized_acc_info
  end

  @tag :rlp_test
  test "Block serialization", setup do
    # currently, serialization is being tested with genesis block only, will be changed after PR regarding #228 is merged.
    block = create_data(Block)
    serialized_block = Header.rlp_encode(block)
    deserialized_block = Header.rlp_decode(serialized_block)
    assert deserialized_block = block
  end

  @tag :rlp_test
  test "Oracle interaction objects serialization", setup do
    oracle_query_chainstate = create_data(OracleQuery)
    serialized_orc_obj = Oracle.rlp_encode(oracle_query_chainstate, :interaction_object)
    {:ok, deserialized_orc_obj} = Oracle.rlp_decode(serialized_orc_obj)
    assert oracle_query_chainstate = deserialized_orc_obj
  end

  @tag :rlp_test
  test "Registered oracles serialization", setup do
    oracle_registered_chainstate = create_data(Oracle)
    serialized_orc = Oracle.rlp_encode(oracle_registered_chainstate, :registered_oracle)
    {:ok, deserialized_orc} = Oracle.rlp_decode(serialized_orc)
    assert oracle_registered_chainstate = deserialized_orc
  end

  @tag :rlp_test
  test "Naming System TX's serialization", setup do
    naming_pre_claim_tx = create_data(NameClaimTx)
    serialized_preclaim_tx = DataTx.rlp_encode(naming_pre_claim_tx)
    deserialized_preclaim_tx = DataTx.rlp_decode(serialized_preclaim_tx)
    assert naming_pre_claim_tx = deserialized_preclaim_tx

    naming_claim_tx = create_data(NameClaimTx)
    serialized_claim_tx = DataTx.rlp_encode(naming_claim_tx)
    deserialized_claim_tx = DataTx.rlp_decode(serialized_claim_tx)
    assert naming_claim_tx = deserialized_claim_tx

    naming_update_tx = create_data(NameUpdateTx)
    serialized_update_tx = DataTx.rlp_encode(naming_update_tx)
    deserialized_update_tx = DataTx.rlp_decode(serialized_update_tx)
    assert naming_update_tx = deserialized_update_tx

    naming_transfer_tx = create_data(NameTransferTx)
    serialized_transfer_tx = DataTx.rlp_encode(naming_transfer_tx)
    deserialized_transfer_tx = DataTx.rlp_decode(serialized_transfer_tx)
    assert naming_transfer_tx = deserialized_transfer_tx
  end

  @tag :rlp_test
  test "Naming System chainstate structures serialization", setup do
    name_state = create_data(Name)
    serialized_name_state = Naming.rlp_encode(name_state, :name)
    {:ok, deserialized_name_state} = Naming.rlp_decode(serialized_name_state)
    assert deserialized_name_state = name_state

    name_commitment = create_data(NameCommitment)
    serialized_name_commitment = Naming.rlp_encode(name_commitment, :name_commitment)
    {:ok, deserialized_name_commitment} = Naming.rlp_decode(serialized_name_commitment)
    assert deserialized_name_commitment = name_commitment
  end

  def create_data(data_type) do
    case data_type do
      SpendTx ->
        DataTx.init(
          data_type,
          %{amount: 100, receiver: <<1, 2, 3>>, version: 1},
          Wallet.get_public_key(),
          100,
          Chain.lowest_valid_nonce()
        )

      CoinbaseTx ->
        List.last(Chain.top_block().txs)

      SignedTx ->
        {:ok, signed_tx} = Account.spend(Aecore.Wallet.Worker.get_public_key("M/0/1"), 100, 20)
        signed_tx

      Oracle ->
        %{
          expires: 10,
          owner:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          query_fee: 5,
          query_format: %{
            "properties" => %{"currency" => %{"type" => "string"}},
            "type" => "object"
          },
          response_format: %{
            "properties" => %{"currency" => %{"type" => "string"}},
            "type" => "object"
          }
        }

      OracleQuery ->
        %{
          expires: 9,
          fee: 5,
          has_response: false,
          oracle_address:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          query: %{"currency" => "USD"},
          response: :undefined,
          response_ttl: 86000,
          sender_address:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          sender_nonce: 4
        }

      Block ->
        Block.genesis_block()

      Account ->
        {%Aecore.Chain.Chainstate{
           accounts:
             {1,
              {<<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4,
                 236, 181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
               <<231, 10, 1, 161, 3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138,
                 35, 63, 33, 4, 236, 181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199,
                 73, 102, 128, 1, 100>>,
               <<165, 213, 247, 84, 246, 15, 80, 32, 192, 81, 141, 192, 203, 23, 180, 252, 121,
                 239, 93, 131, 134, 195, 134, 13, 193, 43, 97, 225, 196, 18, 87, 180>>}},
           oracles: %{interaction_objects: %{}, registered_oracles: %{}}
         },
         <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236, 181,
           172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>}

      NamePreClaimTx ->
        %Aecore.Tx.DataTx{
          fee: 5,
          nonce: 1,
          payload: %Aecore.Naming.Tx.NamePreClaimTx{
            commitment:
              <<1, 168, 130, 92, 49, 3, 219, 12, 26, 208, 240, 226, 92, 7, 216, 30, 22, 168, 99,
                121, 127, 147, 123, 47, 116, 13, 204, 240, 229, 180, 128, 222>>
          },
          senders: [
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>
          ],
          type: Aecore.Naming.Tx.NamePreClaimTx
        }

      NameClaimTx ->
        %Aecore.Tx.DataTx{
          fee: 5,
          nonce: 2,
          payload: %Aecore.Naming.Tx.NameClaimTx{
            name: "test.aet",
            name_salt:
              <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 1>>
          },
          senders: [
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>
          ],
          type: Aecore.Naming.Tx.NameClaimTx
        }

      NameUpdateTx ->
        %Aecore.Tx.DataTx{
          fee: 5,
          nonce: 3,
          payload: %Aecore.Naming.Tx.NameUpdateTx{
            client_ttl: 86400,
            expire_by: 50003,
            hash:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            pointers: "{\"test\": 2}"
          },
          senders: [
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>
          ],
          type: Aecore.Naming.Tx.NameUpdateTx
        }

      NameTransferTx ->
        %Aecore.Tx.DataTx{
          fee: 5,
          nonce: 4,
          payload: %Aecore.Naming.Tx.NameTransferTx{
            hash:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            target:
              <<3, 205, 248, 121, 87, 10, 174, 234, 93, 138, 204, 195, 19, 139, 145, 177, 240,
                209, 81, 28, 50, 184, 33, 185, 198, 195, 193, 6, 245, 133, 117, 141, 39>>
          },
          senders: [
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>
          ],
          type: Aecore.Naming.Tx.NameTransferTx
        }

      NameRevokeTx ->
        %Aecore.Tx.DataTx{
          fee: 5,
          nonce: 1,
          payload: %Aecore.Naming.Tx.NameRevokeTx{
            hash:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>
          },
          senders: [
            <<3, 205, 248, 121, 87, 10, 174, 234, 93, 138, 204, 195, 19, 139, 145, 177, 240, 209,
              81, 28, 50, 184, 33, 185, 198, 195, 193, 6, 245, 133, 117, 141, 39>>
          ],
          type: Aecore.Naming.Tx.NameRevokeTx
        }

      Name ->
        %{
          expires: 50003,
          hash:
            <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
              186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
          owner:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          pointers: [],
          status: :claimed,
          ttl: 86400
        }

      NameCommitment ->
        %{
          hash:
            <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
              186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
          owner:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          created: 8500,
          expires: 86400
        }
    end
  end
end
