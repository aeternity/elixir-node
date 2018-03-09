defmodule Aecore.Structures.OracleResponseTxData do

  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  @type t :: %OracleResponseTxData{
    operator: binary(),
    oracle_address: binary(),
    response: map(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [:operator,
             :oracle_address,
             :response,
             :fee,
             :nonce]
  use ExConstructor

  @spec create(binary(), any(), integer()) :: OracleResponseTxData.t()
  def create(oracle_address, response, fee) do
    registered_oracles = Chain.registered_oracles()
    response_format = registered_oracles[oracle_address].data.response_format
    if(Oracle.data_valid?(response_format, response)) do
      {:ok, pubkey} = Keys.pubkey()
      %OracleResponseTxData{operator: pubkey, oracle_address: oracle_address,
                            response: response, fee: fee,
                            nonce: Chain.lowest_valid_nonce()}
    else
      :error
    end
  end
end
