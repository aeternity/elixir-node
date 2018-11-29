defmodule Aecore.Chain.MicroBlock do
  @moduledoc """
  Module defining the MicroBlock structure
  """
  alias Aecore.Chain.MicroBlock
  alias Aecore.Chain.MicroHeader
  alias Aecore.Tx.SignedTx

  @type t :: %MicroBlock{
          header: MicroHeader.t(),
          txs: list(SignedTx.t())
        }

  defstruct [:header, :txs]
  @rlp_tag 101

  def encode_to_binary(%MicroBlock{header: header, txs: txs}) do
    encoded_header = MicroHeader.encode_to_binary(header)

    encoded_txs =
      for tx <- txs do
        SignedTx.rlp_encode(tx)
      end

    # TODO implement PoF
    encoded_pof = <<>>
    encoded_rest_data = ExRLP.encode([@rlp_tag, header.version, encoded_txs, encoded_pof])
    <<encoded_header::binary, encoded_rest_data::binary>>
  end
end
