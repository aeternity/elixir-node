defmodule Aecore.Contract.CallStateTree do
  @moduledoc """
  Top level call state tree.
  """
  use Aecore.Util.StateTrees, [:calls, Aecore.Contract.Call]

  alias Aecore.Chain.Chainstate
  alias Aecore.Contract.Call
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias MerklePatriciaTree.Trie

  @typedoc "Calls tree"
  @type calls_state() :: Trie.t()

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

  @spec get_call_gas_used(calls_state(), Keys.pubkey(), Keys.pubkey(), non_neg_integer()) ::
          non_neg_integer
  def get_call_gas_used(call_state_tree, contract_id, sender_address, sender_nonce) do
    call_id = Call.id(sender_address, sender_nonce, contract_id)
    call_tree_id = construct_call_tree_id(contract_id, call_id)

    call = get_call(call_state_tree, call_tree_id)
    call.gas_used
  end

  @spec construct_call_tree_id(Identifier.t(), binary()) :: binary()
  def construct_call_tree_id(%Identifier{value: contract_id}, call_id) do
    construct_call_tree_id(contract_id, call_id)
  end

  def construct_call_tree_id(contract_id, call_id) do
    <<contract_id::binary, call_id::binary>>
  end

  @spec process_struct(Call.t(), binary(), calls_state()) :: Call.t() | {:error, String.t()}
  def process_struct(%Call{} = deserialized_value, _key, _tree) do
    deserialized_value
  end

  def process_struct(deserialized_value, _key, _tree) do
    {:error,
     "#{__MODULE__}: Invalid data type: #{deserialized_value.__struct__} but expected %Call{}"}
  end
end
