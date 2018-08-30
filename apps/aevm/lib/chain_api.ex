defmodule Aevm.ChainApi do
  alias Aecore.Keys

  @type chain_state :: any()

  @type store :: %{binary() => binary()}

  @type exception :: :out_of_gas

  @type call_result :: %{
    result: binary() | exception(),
    gas_spent: non_neg_integer()
  }

  @callback get_balance(account :: Keys.pubkey(), state :: chain_state()) :: non_neg_integer()

  @callback call_contract(
              contract :: Keys.pubkey(),
              gas :: non_neg_integer(),
              value :: non_neg_integer(),
              call_data :: binary(),
              call_stack :: [non_neg_integer()],
              state :: chain_state()
            ) :: {:ok, call_result(), chain_state()} | {:error, term()}

  @callback get_store(chain_state()) :: store()

  @callback set_store(store(), chain_state()) :: chain_state()
end
