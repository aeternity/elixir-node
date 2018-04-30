defmodule AecoreSerializationTest do
  use ExUnit.Case

  @moduledoc """
  Unit test for RLP data serialization/deserialization
  """
  alias Aecore.Chain.Header
  alias Aecore.Account.Tx.SpendTx
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

  @tag RLP_test
  test "SignedTx with DataTx inside serialization", setup do
    Miner.mine_sync_block_to_chain()
    signedtx = create_data(SignedTx)

    deserialized_signedtx =
      signedtx
      |> SignedTx.rlp_encode()
      |> SignedTx.rlp_decode()

    assert deserialized_signedtx = signedtx
  end

  @tag RLP_test
  test "DataTx(SpendTx) serialization", setup do
    Miner.mine_sync_block_to_chain()
    spendtx = create_data(SpendTx)

    deserialized_spendtx =
      spendtx
      |> DataTx.rlp_encode()
      |> DataTx.rlp_decode()

    assert deserialized_spendtx = spendtx
  end

  # @tag RLP_test
  # test "Account chain-state serialization" do  TODO : Found a bug in account chainstate serializations
  #   {account, pkey} = create_data(Account)
  #   serialized_acc_info = Chainstate.rlp_encode(account, pkey)
  #   IO.inspect serialized_acc_info
  #   deserialized_acc_info = Chainstate.rlp_decode(serialized_acc_info)
  #   assert account = deserialized_acc_info
  # end
  @tag RLP_test
  test "Block serialization", setup do
    # currently, serialization is being tested with genesis block only
    block = create_data(Block)
    serialized_block = Header.rlp_encode(block)
    deserialized_block = Header.rlp_decode(serialized_block)
    assert deserialized_block = block
  end

  test "Oracle interaction objects serialization", setup do
  end

  test "Registered oracles serialization", setup do
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
          response: "undefined",
          response_ttl: <<131, 109, 0, 0, 0, 1, 5>>,
          sender_address:
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
          sender_nonce: <<131, 109, 0, 0, 0, 1, 2>>
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
    end
  end

  #  def deserialized_data(data_type) do
  #    case data_type do
  #       #SpendTx -> DataTx.init(tx_type, ,)  
  #       SignedTx -> {:ok, signed_tx} = Account.spend(Aecore.Wallet.Worker.get_public_key("M/0/1"), 100,20)
  #       signed_tx
  #       #Oracle -> TODO: add all commented cases when PR about oracle adjustment is accepted and merged
  #       #OracleQuery -> 
  #       #OracleExtendTx ->
  #       #OracleRegisterTx -> 
  #       #OracleQueryTx ->
  #       Block -> Chain.top_block
  #       Account -> {Chain.chain_state , Aecore.Wallet.Worker.get_public_key("M/0/1")}
  #       CoinbaseTx -> 
  #         %Aecore.Tx.SignedTx{
  #           data: %Aecore.Tx.DataTx{
  #           fee: 0,
  #           nonce: 0,
  #           payload: %Aecore.Account.Tx.SpendTx{
  #           amount: 100,
  #           receiver: <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236,
  #           138, 35, 63, 33, 4, 236, 181, 172, 160, 156, 141, 129, 143, 104,
  #           133, 128, 109, 199, 73, 102>>,
  #           version: 1
  #           },
  #           sender: nil,
  #           type: Aecore.Account.Tx.SpendTx
  #       }, 
  #       signature: [<<0>>] # [<<0>>] is added because of lack of coinbase tx as separate type 
  #   }

  #    end
  #  end
end
