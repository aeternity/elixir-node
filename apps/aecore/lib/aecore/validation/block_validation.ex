defmodule Aecore.Validation.BlockValidation do

  alias Aecore.Keys.Worker, as: KeyManager

  def validate_block(new_block, previous_block) do
    new_block_header_hash = block_header_hash(new_block)
    prev_block_header_hash = block_header_hash(previous_block)
    {new_block_header_hash_int, _} = Integer.parse(new_block_header_hash, 16)

    cond do
      new_block.header.prev_hash != prev_block_header_hash ->
        {:error, "Incorrect previous hash"}
      previous_block.header.height + 1 != new_block.header.height ->
        {:error, "Incorrect height"}
      new_block_header_hash_int >= new_block.header.difficulty_target ->
        {:error, "Header hash doesnt meet the difficulty target"}
      !new_block |> validate_block_transactions |> Enum.all? ->
        {:error, "One or more transactions not valid"}
      new_block.header.txs_hash != calculate_root_hash(new_block)
    end
  end

  def block_header_hash (block) do
    block_header_bin = :erlang.term_to_binary(block.header)
    Base.encode16(:crypto.hash(:sha256, block_header_bin))
  end

  def validate_block_transactions(block) do
    for transaction <- block.txs do
      signed = KeyManager.sign(transaction.data)
      {_, pubkey} = KeyManager.pubkey()
      KeyManager.verify(transaction.data, signed.signature, pubkey)
    end
  end

  def calculate_root_hash(block) do
    merkle_tree = :gb_merkle_trees.empty
    merkle_tree = for transaction <- block.txs do
      transaction_data_bin = :erlang.term_to_binary(transaction.data)
      :gb_merkle_trees.enter(:crypto.hash(:sha256, transaction_data_bin),
        transaction_data_bin,
        merkle_tree)
    end
    merkle_tree |> :gb_merkle_trees.root_hash() |> Base.encode16()
  end

end
