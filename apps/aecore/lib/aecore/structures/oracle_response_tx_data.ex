defmodule Aecore.Structures.OracleResponseTxData do

  alias __MODULE__
  alias Aecore.OraclePrototype.OracleTxValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  @type t :: %OracleResponseTxData{
    operator: binary(),
    oracle_hash: binary(),
    response: map(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [:operator,
             :oracle_hash,
             :response,
             :fee,
             :nonce]
  use ExConstructor

  @spec create(binary(), any(), integer(), integer()) :: %OracleResponseTxData{}
  def create(oracle_hash, response, fee, nonce) do
    registered_oracles = Chain.registered_oracles()
    response_format = registered_oracles[oracle_hash].data.response_format
    if(OracleTxValidation.data_valid?(response_format, response)) do
      {:ok, pubkey} = Keys.pubkey()
      %OracleResponseTxData{operator: pubkey, oracle_hash: oracle_hash,
                            response: response, fee: fee, nonce: nonce}
    else
      :error
    end
  end

  @spec is_oracle_response_tx(map()) :: boolean()
  def is_oracle_response_tx(tx) do
    Map.has_key?(tx, "operator") && Map.has_key?(tx, "oracle_hash") &&
    Map.has_key?(tx, "response") && Map.has_key?(tx, "fee") &&
    Map.has_key?(tx, "nonce")
  end
end
