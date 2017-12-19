defmodule Aecore.Structures.OracleResponseTxData do
  defstruct [:operator,
             :query_transaction_hash,
             :response,
             :fee]
end
