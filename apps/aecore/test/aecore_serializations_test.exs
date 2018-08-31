defmodule AecoreSerializationTest do
  use ExUnit.Case

  @moduledoc """
  Unit test for RLP data serialization/deserialization
  """
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Oracle.{OracleQuery, Oracle}
  alias Aecore.Account.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Keys
  alias Aecore.Account.Account
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Block
  alias Aecore.Naming.{Name, NameCommitment}
  alias Aecore.Naming.Tx.{NamePreClaimTx, NameClaimTx, NameUpdateTx.NameTransferTx}
  alias Aecore.Chain.Identifier

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  @tag :rlp_test
  test "SignedTx with DataTx inside serialization" do
    Miner.mine_sync_block_to_chain()
    signedtx = create_data(SignedTx, :elixir)

    {:ok, deserialized_signedtx} =
      signedtx
      |> SignedTx.rlp_encode()
      |> SignedTx.rlp_decode()

    assert deserialized_signedtx == signedtx
  end

  @tag :rlp_test
  test "DataTx(SpendTx) serialization" do
    Miner.mine_sync_block_to_chain()
    spendtx = create_data(SpendTx, :elixir)

    {:ok, deserialized_spendtx} =
      spendtx
      |> DataTx.rlp_encode()
      |> DataTx.rlp_decode()

    assert deserialized_spendtx == spendtx
  end

  @tag :rlp_test
  test "Block serialization" do
    block = create_data(Block, :elixir)
    serialized_block = Block.rlp_encode(block)
    {:ok, deserialized_block} = Block.rlp_decode(serialized_block)
    assert deserialized_block == block
  end

  @tag :rlp_test
  test "Oracle interaction objects serialization" do
    oracle_query_chainstate = create_data(OracleQuery, :elixir)
    serialized_orc_obj = OracleQuery.rlp_encode(oracle_query_chainstate)
    {:ok, deserialized_orc_obj} = OracleQuery.rlp_decode(serialized_orc_obj)

    assert oracle_query_chainstate == deserialized_orc_obj
  end

  @tag :rlp_test
  test "Registered oracles serialization" do
    oracle_registered_chainstate = create_data(Oracle, :elixir)
    serialized_orc = Oracle.rlp_encode(oracle_registered_chainstate)
    {:ok, deserialized_orc} = Oracle.rlp_decode(serialized_orc)

    assert oracle_registered_chainstate == deserialized_orc
  end

  @tag :rlp_test
  test "Naming System TX's serialization" do
    naming_pre_claim_tx = create_data(NamePreClaimTx, :elixir)
    serialized_preclaim_tx = DataTx.rlp_encode(naming_pre_claim_tx)
    {:ok, deserialized_preclaim_tx} = DataTx.rlp_decode(serialized_preclaim_tx)
    assert naming_pre_claim_tx == deserialized_preclaim_tx

    naming_claim_tx = create_data(NameClaimTx, :elixir)
    serialized_claim_tx = DataTx.rlp_encode(naming_claim_tx)
    {:ok, deserialized_claim_tx} = DataTx.rlp_decode(serialized_claim_tx)
    assert naming_claim_tx == deserialized_claim_tx

    naming_update_tx = create_data(NameUpdateTx, :elixir)
    serialized_update_tx = DataTx.rlp_encode(naming_update_tx)
    {:ok, deserialized_update_tx} = DataTx.rlp_decode(serialized_update_tx)
    assert naming_update_tx == deserialized_update_tx

    naming_transfer_tx = create_data(NameTransferTx, :elixir)
    serialized_transfer_tx = DataTx.rlp_encode(naming_transfer_tx)
    {:ok, deserialized_transfer_tx} = DataTx.rlp_decode(serialized_transfer_tx)
    assert naming_transfer_tx == deserialized_transfer_tx
  end

  @tag :rlp_test
  test "Naming System chainstate structures serialization" do
    name_state = create_data(Name, :elixir)
    serialized_name_state = Name.rlp_encode(name_state)
    {:ok, deserialized_name_state} = Name.rlp_decode(serialized_name_state)
    deserialized_name_state1 = %Name{deserialized_name_state | hash: name_state.hash}
    assert deserialized_name_state1 == name_state

    name_commitment = create_data(NameCommitment, :elixir)
    serialized_name_commitment = NameCommitment.rlp_encode(name_commitment)
    {:ok, deserialized_name_commitment} = NameCommitment.rlp_decode(serialized_name_commitment)

    updated_deserialized_name_commitment = %NameCommitment{
      deserialized_name_commitment
      | hash: name_commitment.hash
    }

    assert updated_deserialized_name_commitment == name_commitment
  end

  @tag :rlp_test
  @tag timeout: 120_000
  test "Epoch RLP-encoded block deserialization" do
    epoch_serialized_block = create_data(Block, :erlang)
    {:ok, deserialized_epoch_block} = Block.rlp_decode(epoch_serialized_block)
    assert %Block{} = deserialized_epoch_block
  end

  def create_data(data_type, :elixir) do
    %{public: acc2_pub, secret: acc2_priv} = :enacl.sign_keypair()

    case data_type do
      SpendTx ->
        DataTx.init(
          data_type,
          %{amount: 100, receiver: <<1, 2, 3>>, version: 1, payload: <<"payload">>},
          elem(Keys.keypair(:sign), 0),
          100,
          Chain.lowest_valid_nonce()
        )

      SignedTx ->
        {:ok, signed_tx} = Account.spend(acc2_pub, 100, 20, <<"payload">>)

        signed_tx

      Oracle ->
        %Oracle{
          expires: 10,
          owner: %Identifier{value: "", type: :oracle},
          query_fee: 5,
          query_format: "foo: bar",
          response_format: "boolean"
        }

      OracleQuery ->
        %OracleQuery{
          expires: 9,
          fee: 5,
          has_response: false,
          oracle_address:
            <<183, 82, 43, 247, 176, 2, 118, 61, 57, 250, 89, 250, 197, 31, 24, 159, 228, 23, 4,
              75, 105, 32, 60, 200, 63, 71, 223, 83, 201, 235, 246, 16>>,
          query: "foo: bar",
          response: :undefined,
          response_ttl: 86_000,
          sender_address:
            <<183, 82, 43, 247, 176, 2, 118, 61, 57, 250, 89, 250, 197, 31, 24, 159, 228, 23, 4,
              75, 105, 32, 60, 200, 63, 71, 223, 83, 201, 235, 246, 16>>,
          sender_nonce: 4
        }

      Block ->
        Miner.mine_sync_block_to_chain()
        %{public: pk1, secret: _} = :enacl.sign_keypair()
        TestUtils.miner_spend(pk1, 10)
        TestUtils.assert_transactions_mined()
        block = Chain.top_block()
        assert length(block.txs) == 1
        block

      NamePreClaimTx ->
        {:ok, pre_claim} = Account.pre_claim("test.aet", 123, 50)
        pre_claim.data

      NameClaimTx ->
        {:ok, claim} = Account.claim("test.aet", 123, 50)
        claim.data

      NameUpdateTx ->
        {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 50, 5000, 50)
        update.data

      NameTransferTx ->
        transfer_to_pub = acc2_pub

        {:ok, transfer} = Account.name_transfer("test.aet", transfer_to_pub, 50)
        transfer.data

      NameRevokeTx ->
        transfer_to_priv = acc2_priv
        transfer_to_pub = acc2_pub
        next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1

        {:ok, revoke} =
          Account.name_revoke(transfer_to_pub, transfer_to_priv, "test.aet", 50, next_nonce)

        revoke.data

      Name ->
        %Name{
          expires: 50_003,
          hash: %Identifier{
            value:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            type: :name
          },
          owner:
            <<183, 82, 43, 247, 176, 2, 118, 61, 57, 250, 89, 250, 197, 31, 24, 159, 228, 23, 4,
              75, 105, 32, 60, 200, 63, 71, 223, 83, 201, 235, 246, 16>>,
          pointers: [],
          status: :claimed,
          client_ttl: 86_400
        }

      NameCommitment ->
        %NameCommitment{
          hash: %Identifier{
            value:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            type: :name
          },
          owner:
            <<183, 82, 43, 247, 176, 2, 118, 61, 57, 250, 89, 250, 197, 31, 24, 159, 228, 23, 4,
              75, 105, 32, 60, 200, 63, 71, 223, 83, 201, 235, 246, 16>>,
          created: 8500,
          expires: 86_400
        }
    end
  end

  def create_data(data_type, :erlang) do
    case data_type do
      Block ->
        Base.decode64!(
          "+QFWZA65AVAAAAAAAAAADgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOXmmv/3SQdDjexUzDIgBElzLw7DGKrzrhx70NclO9hFAAAAACEA//8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADA"
        )
    end
  end
end
