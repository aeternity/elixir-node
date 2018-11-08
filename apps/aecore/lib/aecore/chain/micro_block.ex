defmodule Aecore.Chain.MicroBlock do
  alias Aecore.Chain.MicroBlock
  alias Aecore.Chain.MicroHeader
  alias Aecore.Tx.SignedTx

  @type t :: %MicroBlock{
          header: MicroHeader.t(),
          txs: list(SignedTx.t())
        }

  defstruct [:header, :txs]
end
