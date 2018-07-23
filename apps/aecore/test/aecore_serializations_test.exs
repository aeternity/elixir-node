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
  alias Aecore.Keys.Wallet
  alias Aecore.Account.Account
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Block
  alias Aecore.Naming.Naming
  alias Aeutil.Serialization
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.BlockValidation
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
  test "SignedTx with DataTx inside serialization", setup do
    Miner.mine_sync_block_to_chain()
    signedtx = create_data(SignedTx, :elixir)

    deserialized_signedtx =
      signedtx
      |> Serialization.rlp_encode(:signedtx)
      |> Serialization.rlp_decode()

    assert deserialized_signedtx = signedtx
  end

  @tag :rlp_test
  test "DataTx(SpendTx) serialization", setup do
    Miner.mine_sync_block_to_chain()
    spendtx = create_data(SpendTx, :elixir)

    deserialized_spendtx =
      spendtx
      |> Serialization.rlp_encode(:tx)
      |> Serialization.rlp_decode()

    assert deserialized_spendtx = spendtx
  end

  @tag :rlp_test
  test "Block serialization", setup do
    block = create_data(Block, :elixir)
    serialized_block = Serialization.rlp_encode(block, :block)
    deserialized_block = Block.rlp_decode(serialized_block)
    assert deserialized_block = block
  end

  @tag :rlp_test
  test "Oracle interaction objects serialization", setup do
    oracle_query_chainstate = create_data(OracleQuery, :elixir)
    serialized_orc_obj = Serialization.rlp_encode(oracle_query_chainstate, :oracle_query)
    {:ok, deserialized_orc_obj} = Serialization.rlp_decode(serialized_orc_obj)
    assert oracle_query_chainstate = deserialized_orc_obj
  end

  @tag :rlp_test
  test "Registered oracles serialization", setup do
    oracle_registered_chainstate = create_data(Oracle, :elixir)
    serialized_orc = Serialization.rlp_encode(oracle_registered_chainstate, :oracle)
    {:ok, deserialized_orc} = Serialization.rlp_decode(serialized_orc)
    assert oracle_registered_chainstate = deserialized_orc
  end

  @tag :rlp_test
  test "Naming System TX's serialization", setup do
    naming_pre_claim_tx = create_data(NameClaimTx, :elixir)
    serialized_preclaim_tx = Serialization.rlp_encode(naming_pre_claim_tx, :tx)
    deserialized_preclaim_tx = Serialization.rlp_decode(serialized_preclaim_tx)
    assert naming_pre_claim_tx = deserialized_preclaim_tx

    naming_claim_tx = create_data(NameClaimTx, :elixir)
    serialized_claim_tx = Serialization.rlp_encode(naming_claim_tx, :tx)
    deserialized_claim_tx = Serialization.rlp_decode(serialized_claim_tx)
    assert naming_claim_tx = deserialized_claim_tx

    naming_update_tx = create_data(NameUpdateTx, :elixir)
    serialized_update_tx = Serialization.rlp_encode(naming_update_tx, :tx)
    deserialized_update_tx = Serialization.rlp_decode(serialized_update_tx)
    assert naming_update_tx = deserialized_update_tx

    naming_transfer_tx = create_data(NameTransferTx, :elixir)
    serialized_transfer_tx = Serialization.rlp_encode(naming_transfer_tx, :tx)
    deserialized_transfer_tx = Serialization.rlp_decode(serialized_transfer_tx)
    assert naming_transfer_tx = deserialized_transfer_tx
  end

  @tag :rlp_test
  test "Naming System chainstate structures serialization", setup do
    name_state = create_data(Name, :elixir)
    serialized_name_state = Serialization.rlp_encode(name_state, :naming_state)
    deserialized_name_state = Serialization.rlp_decode(serialized_name_state)
    assert deserialized_name_state = name_state

    name_commitment = create_data(NameCommitment, :elixir)
    serialized_name_commitment = Serialization.rlp_encode(name_commitment, :name_commitment)
    deserialized_name_commitment = Serialization.rlp_decode(serialized_name_commitment)
    assert deserialized_name_commitment = name_commitment
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
          expires: 24,
          fee: 5,
          has_response: true,
          oracle_address: %Aecore.Chain.Identifier{
            type: :oracle,
            value:
              <<3, 239, 132, 130, 113, 104, 39, 133, 32, 81, 42, 101, 59, 120, 49, 48, 148, 180,
                81, 168, 88, 87, 5, 43, 44, 242, 49, 137, 92, 13, 162, 72, 219>>
          },
          query: %{"currency" => "USD"},
          response: %{"currency" => "BGN"},
          response_ttl: 10,
          sender_address: %Aecore.Chain.Identifier{
            type: :account,
            value:
              <<3, 239, 132, 130, 113, 104, 39, 133, 32, 81, 42, 101, 59, 120, 49, 48, 148, 180,
                81, 168, 88, 87, 5, 43, 44, 242, 49, 137, 92, 13, 162, 72, 219>>
          },
          sender_nonce: 2
        }

      Block ->
        Miner.mine_sync_block_to_chain()
        Chain.top_block()

      NamePreClaimTx ->
        {:ok, pre_claim_tx} = Account.pre_claim("pre_claim.aet", <<"pre_claim_salt">>, 5)
        pre_claim_tx.data

      NameClaimTx ->
        {:ok, claim_tx} = Account.claim("pre_claim.aet", <<"pre_claim_salt">>, 5)
        claim_tx.data

      NameUpdateTx ->
        {:ok, name_update_tx} = Account.name_update("name_update.aet", "{\"test\": 2}", 5)
        name_update_tx.data

      NameTransferTx ->
        {:ok, name_transfer} =
          Account.name_transfer("name_update.aet", Wallet.get_public_key("M/0/1"), 5)

        name_transfer.data

      NameRevokeTx ->
        {:ok, name_revoke} = Account.name_revoke("pre_claim.aet", 10)
        name_revoke.data

      Name ->
        {:ok, identified_hash} =
          Identifier.create_identity(
            <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
              186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            :name
          )

        {:ok, identified_owner} =
          Identifier.create_identity(
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            :account
          )

        %{
          expires: 50_003,
          hash: identified_hash,
          owner: identified_owner,
          pointers: [],
          status: :claimed,
          ttl: 86_400
        }

      NameCommitment ->
        {:ok, identified_commitment_hash} =
          Identifier.create_identity(
            <<231, 243, 33, 35, 150, 21, 97, 180, 218, 143, 116, 2, 115, 40, 134, 218, 47, 133,
              186, 187, 183, 8, 76, 226, 193, 29, 207, 59, 204, 216, 247, 250>>,
            :commitment
          )

        {:ok, identified_owner} =
          Identifier.create_identity(
            <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236,
              181, 172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>,
            :account
          )

        %{
          hash: identified_commitment_hash,
          owner: identified_owner,
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