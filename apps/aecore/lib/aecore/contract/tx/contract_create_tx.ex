defmodule Aecore.Contract.Tx.ContractCreateTx do
  @moduledoc """
  Contains the transaction structure for creating contracts
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__

  @type payload :: %{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  @type t :: %ContractCreateTx{
          code: binary(),
          vm_version: byte(),
          deposit: non_neg_integer(),
          amount: non_neg_integer(),
          gas: non_neg_integer(),
          gas_price: non_neg_integer(),
          call_data: binary()
        }

  defstruct [
    :code,
    :vm_version,
    :deposit,
    :amount,
    :gas,
    :gas_price,
    :call_data
  ]

  @spec init(payload()) :: t()
  def init(%{
        code: code,
        vm_version: vm_version,
        deposit: deposit,
        amount: amount,
        gas: gas,
        gas_price: gas_price,
        call_data: call_data
      }) do
    %ContractCreateTx{
      code: code,
      vm_version: vm_version,
      deposit: deposit,
      amount: amount,
      gas: gas,
      gas_price: gas_price,
      call_data: call_data
    }
  end

  def validate(%ContractCreateTx{deposit: deposit, amount: amount
  , gas: gas, gas_price: gas_price}, data_tx) do
    senders = DataTx.senders(data_tx)
    total_amount = DataTx.fee(data_tx) + amount + deposit + gas * gas_price
  end
end
