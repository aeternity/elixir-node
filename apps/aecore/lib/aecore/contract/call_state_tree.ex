defmodule Aecore.Contract.CallStateTree do
  @moduledoc """
  Top level call state tree.
  """
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier
  alias MerklePatriciaTree.Trie
  alias Aecore.Chain.Chainstate
  alias Aecore.Contract.Call

  @type calls_state() :: Trie.t()
  @type hash :: binary()
  @spec init_empty() :: calls_state()

  def init_empty do
    PatriciaMerkleTree.new(:calls)
  end

  # A new block always starts with an empty calls tree.
  # Calls and return values are only kept for one block.

  @spec prune(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def prune(chainstate, _block_height) do
    %{chainstate | calls: init_empty()}
  end

  @spec insert_call(calls_state(), map()) :: calls_state()
  def insert_call(call_tree, call) do
    contract_id = call.contract_address
    call_id = Call.id(call)
    call_tree_id = construct_call_tree_id(contract_id, call_id)

    serialized = Serialization.rlp_encode(call, :call)
    PatriciaMerkleTree.insert(call_tree, call_tree_id, serialized)
  end

  @spec get_call(calls_state(), binary()) :: calls_state()
  def get_call(calls_tree, key) do
    case PatriciaMerkleTree.lookup(calls_tree, key) do
      {:ok, value} ->
        {:ok, deserialized_call} = Serialization.rlp_decode(value)

        case deserialized_call do
          %{
            :caller_address => caller,
            :caller_nonce => _nonce,
            :height => _block_height,
            :contract_address => address,
            :gas_price => _gas_price,
            :gas_used => _gas_used,
            :return_value => _return_value,
            :return_type => _return_type
          } ->
            {:ok, identified_caller_address} = Identifier.create_identity(caller, :contract)
            {:ok, identified_contract_address} = Identifier.create_identity(address, :contract)

            %{
              deserialized_call
              | caller_address: identified_caller_address,
                contract_address: identified_contract_address
            }
        end

      _ ->
        :none
    end
  end

  @spec root_hash(calls_state()) :: hash()
  def root_hash(calls_tree) do
    PatriciaMerkleTree.root_hash(calls_tree)
  end

  def construct_call_tree_id(contract_id, call_id) do
    <<contract_id.value::binary, call_id::binary>>
  end
end
