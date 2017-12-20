defmodule Aecore.Structures.OracleResponseTxData do

  alias __MODULE__
  alias Aecore.OraclePrototype.OracleTxValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  defstruct [:operator,
             :oracle_hash,
             :response,
             :fee]

  @spec create(binary(), any(), integer()) :: %OracleResponseTxData{}
  def create(oracle_hash, response, fee) do
    registered_oracles = Chain.registered_oracles()
    response_format = registered_oracles[oracle_hash].data.response_format
    if(OracleTxValidation.validate_data(response_format, response)) do
      {:ok, pubkey} = Keys.pubkey()
      %OracleResponseTxData{operator: pubkey,
                            oracle_hash: oracle_hash,
                            response: response,
                            fee: fee}
    else
      :error
    end
  end
end
