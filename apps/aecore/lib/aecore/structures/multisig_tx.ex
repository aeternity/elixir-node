defmodule Aecore.Structures.MultisigTx do

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.MultisigTx

  @type multisig_tx() :: %MultisigTx{}

  defstruct [:data, :signatures]
  use ExConstructor

  @spec is_valid(multisig_tx()) :: boolean()
  def is_valid(tx) do
    not_negative =
      tx.data.lock_amounts
      |> Map.values
      |> Enum.all?(fn(amount) -> amount >= 0 end)
    signature_valid = Keys.verify_tx(tx)
    not_negative && signature_valid
  end

  @spec is_multisig_tx?(map()) :: boolean()
  def is_multisig_tx?(tx) do
    if(Map.has_key?(tx, "signatures") || Map.has_key?(tx, :signatures)) do
      true
    else
      false
    end
  end
end
