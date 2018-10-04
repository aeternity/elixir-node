defmodule Aecore.Contract.CallStateTree do
  @moduledoc """
  Top level call state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Chain.Chainstate
  alias Aecore.Contract.Call
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias MerklePatriciaTree.Trie

  @typedoc "Hash of the tree"
  @type hash :: binary()

  @typedoc "Calls tree"
  @type calls_state() :: Trie.t()

  @spec name() :: atom()
  def name(), do: :calls

  # A new block always starts with an empty calls tree.
  # Calls and return values are only kept for one block.

  @spec prune(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def prune(chainstate, _block_height) do
    %{chainstate | calls: init_empty()}
  end

  @spec insert_call(calls_state(), Call.t()) :: calls_state()
  def insert_call(call_tree, %Call{contract_address: contract_address} = call) do
    call_id = Call.id(call)
    call_tree_id = construct_call_tree_id(contract_address, call_id)

    serialized = Serialization.rlp_encode(call)
    PatriciaMerkleTree.insert(call_tree, call_tree_id, serialized)
  end

  @spec get_call(calls_state(), binary()) :: calls_state()
  def get_call(calls_tree, key) do
    case PatriciaMerkleTree.lookup(calls_tree, key) do
      {:ok, serialized} ->
        {:ok, deserialized_call} = Serialization.rlp_decode_anything(serialized)
        deserialized_call

      _ ->
        :none
    end
  end

  @spec root_hash(calls_state()) :: hash()
  def root_hash(calls_tree) do
    PatriciaMerkleTree.root_hash(calls_tree)
  end

  @spec construct_call_tree_id(binary(), binary()) :: binary()
  def construct_call_tree_id(contract_id, call_id) do
    <<contract_id.value::binary, call_id::binary>>
  end
end
