defmodule AecoreSerializationTest do
  use ExUnit.Case

  @moduledoc """
  Unit test for RLP data serialization/deserialization
  """
  alias Aecore.Account.Account
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Chain.Block
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys.Wallet
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

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
  test "SignedTx with DataTx inside serialization" do
    Miner.mine_sync_block_to_chain()
    signedtx = create_data(SignedTx, :elixir)

    deserialized_signedtx =
      signedtx
      |> Serialization.rlp_encode(:signedtx)
      |> Serialization.rlp_decode()

    assert deserialized_signedtx == signedtx
  end

  @tag :rlp_test
  test "DataTx(SpendTx) serialization" do
    Miner.mine_sync_block_to_chain()
    spendtx = create_data(SpendTx, :elixir)

    deserialized_spendtx =
      spendtx
      |> Serialization.rlp_encode(:tx)
      |> Serialization.rlp_decode()

    assert deserialized_spendtx == spendtx
  end

  @tag :rlp_test
  test "Block serialization" do
    block = create_data(Block, :elixir)
    serialized_block = Serialization.rlp_encode(block, :block)
    deserialized_block = Serialization.rlp_decode(serialized_block)
    assert deserialized_block == block
  end

  @tag :rlp_test
  test "Oracle interaction objects serialization" do
    oracle_query_chainstate = create_data(OracleQuery, :elixir)
    serialized_orc_obj = Serialization.rlp_encode(oracle_query_chainstate, :oracle_query)
    {:ok, deserialized_orc_obj} = Serialization.rlp_decode(serialized_orc_obj)

    {:ok, identified_owner} =
      Identifier.create_identity(deserialized_orc_obj.oracle_address, :oracle)

    {:ok, identified_sender} =
      Identifier.create_identity(deserialized_orc_obj.sender_address, :account)

    assert oracle_query_chainstate == %{
             deserialized_orc_obj
             | oracle_address: identified_owner,
               sender_address: identified_sender
           }
  end

  @tag :rlp_test
  test "Registered oracles serialization" do
    oracle_registered_chainstate = create_data(Oracle, :elixir)
    serialized_orc = Serialization.rlp_encode(oracle_registered_chainstate, :oracle)
    {:ok, deserialized_orc} = Serialization.rlp_decode(serialized_orc)

    # {:ok, identified_orc_address} = Identifier.create_identity( deserialized_orc.oracle_address, :oracle)
    # {:ok, identified_sender_address} = Identifier.create_identity( deserialized_orc.sender_address, :account)
    # | oracle_address: identified_orc_address, sender_address: identified_sender_address}
    assert oracle_registered_chainstate == deserialized_orc
  end

  @tag :rlp_test
  test "Naming System TX's serialization" do
    naming_pre_claim_tx = create_data(NamePreClaimTx, :elixir)
    serialized_preclaim_tx = Serialization.rlp_encode(naming_pre_claim_tx, :tx)
    deserialized_preclaim_tx = Serialization.rlp_decode(serialized_preclaim_tx)
    assert naming_pre_claim_tx == deserialized_preclaim_tx

    naming_claim_tx = create_data(NameClaimTx, :elixir)
    serialized_claim_tx = Serialization.rlp_encode(naming_claim_tx, :tx)
    deserialized_claim_tx = Serialization.rlp_decode(serialized_claim_tx)
    assert naming_claim_tx == deserialized_claim_tx

    naming_update_tx = create_data(NameUpdateTx, :elixir)
    serialized_update_tx = Serialization.rlp_encode(naming_update_tx, :tx)
    deserialized_update_tx = Serialization.rlp_decode(serialized_update_tx)
    assert naming_update_tx == deserialized_update_tx

    naming_transfer_tx = create_data(NameTransferTx, :elixir)
    serialized_transfer_tx = Serialization.rlp_encode(naming_transfer_tx, :tx)
    deserialized_transfer_tx = Serialization.rlp_decode(serialized_transfer_tx)
    assert naming_transfer_tx == deserialized_transfer_tx
  end

  # Uncomment this check after the pubkey is implemented with :ed25519
  # @tag :rlp_test
  # @tag timeout: 120_000
  # test "Epoch RLP-encoded block deserialization", setup do
  # epoch_serialized_block = create_data(Block, :erlang)
  # deserialized_epoch_block = Serialization.rlp_decode(epoch_serialized_block)
  # assert %Block{} = deserialized_epoch_block
  # end

  def create_data(data_type, :elixir) do
    case data_type do
      SpendTx ->
        DataTx.init(
          data_type,
          %{amount: 100, receiver: <<1, 2, 3>>, version: 1, payload: <<"payload">>},
          Wallet.get_public_key(),
          100,
          Chain.lowest_valid_nonce()
        )

      SignedTx ->
        {:ok, signed_tx} = Account.spend(Wallet.get_public_key("M/0/1"), 100, 20, <<"payload">>)

        signed_tx

      Oracle ->
        %{
          expires: 10,
          owner: %Identifier{value: "", type: :oracle},
          query_fee: 5,
          query_format: "foo: bar",
          response_format: "boolean"
        }

      OracleQuery ->
        %{
          expires: 9,
          fee: 5,
          has_response: false,
          oracle_address: %Identifier{
            value:
              <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
                181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            type: :oracle
          },
          query: "foo: bar",
          response: :undefined,
          response_ttl: 86_000,
          sender_address: %Identifier{
            value:
              <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
                181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            type: :account
          },
          sender_nonce: 4
        }

      Block ->
        Miner.mine_sync_block_to_chain()
        Chain.top_block()

      NamePreClaimTx ->
        {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 50)
        pre_claim.data

      NameClaimTx ->
        {:ok, claim} = Account.claim("test.aet", <<1::256>>, 50)
        claim.data

      NameUpdateTx ->
        {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 50)
        update.data

      NameTransferTx ->
        transfer_to_priv = Wallet.get_private_key("m/0/1")

        transfer_to_pub = Wallet.to_public_key(transfer_to_priv)

        {:ok, transfer} = Account.name_transfer("test.aet", transfer_to_pub, 50)
        transfer.data

      NameRevokeTx ->
        transfer_to_priv = Wallet.get_private_key("m/0/1")

        transfer_to_pub = Wallet.to_public_key(transfer_to_priv)
        next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1

        {:ok, revoke} =
          Account.name_revoke(transfer_to_pub, transfer_to_priv, "test.aet", 50, next_nonce)

        revoke.data

      Name ->
        %{
          expires: 50_003,
          hash: %Identifier{
            value:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            type: :name
          },
          owner: %Identifier{
            value:
              <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
                181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            type: :account
          },
          pointers: [],
          status: :claimed,
          ttl: 86_400
        }

      NameCommitment ->
        %{
          hash: %Identifier{
            value:
              <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
                186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            type: :name
          },
          owner: %Identifier{
            value:
              <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
                181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            type: :account
          },
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
