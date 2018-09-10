defmodule GasCodes do
  @moduledoc """
  Module containing macro definitions for gas cost
  From https://github.com/ethereum/go-ethereum/blob/master/params/gas_table.go
  """

  # credo:disable-for-this-file

  # Nothing paid for operations of the set Wzero.
  defmacro _GZERO do quote do: 0 end

  #Amount of gas to pay for operations of the set Wbase.
  defmacro _GBASE do quote do: 2 end

  # Amount of gas to pay for operations of the set Wverylow.
  defmacro _GVERYLOW do quote do: 3 end

  # Amount of gas to pay for operations of the set Wlow.
  defmacro _GLOW do quote do: 5 end

  # Amount of gas to pay for operations of the set Wmid
  defmacro _GMID do quote do: 8 end

  # Amount of gas to pay for operations of the set Whigh.
  defmacro _GHIGH do quote do: 10 end

  # Amount of gas to pay for operations of the set Wextcode.
  defmacro _GEXTCODE do quote do: 700 end

  # Amount of gas to pay for operations of the set Wextcodesize.
  defmacro _GEXTCODESIZE do quote do: 20 end

  # Amount of gas to pay for operations of the set Wextcodecopy.
  defmacro _GEXTCODECOPY do quote do: 20 end

  # Amount of gas to pay for a BALANCE operation.
  defmacro _GBALANCE do quote do: 20 end

  # Paid for a SLOAD operation.
  defmacro _GSLOAD do quote do: 50 end

  # Paid for a JUMPDEST operation.
  defmacro _GJUMPDEST do quote do: 1 end

  # Paid for an SSTORE operation when the storage value is set to
  # non-zero from zero.
  defmacro _GSSET do quote do: 20000 end

  # Paid for an SSTORE operation when the storage value’s zeroness
  # remains unchanged or is set to zero.
  defmacro _GSRESET do quote do: 5000 end

  # Refund given (added into refund counter) when the storage value is
  # set to zero from non-zero.
  defmacro _RSCLEAR do quote do: 15000 end

  # Refund given (added into refund counter) for self-destructing an
  # account.
  defmacro _RSELFDESTRUCT do quote do: 24000 end

  # Amount of gas to pay for a SELFDESTRUCT operation
  defmacro _GSELFDESTRUCT do quote do: 5000 end

  # Paid for a CREATE operation.
  defmacro _GCREATE do quote do: 32000 end

  # Paid per byte for a CREATE operation to succeed in placing code
  # into state.
  defmacro _GCODEDEPOSIT do quote do: 200 end

  # Paid for a CALL operation.
  defmacro _GCALL do quote do: 40 end

  # Paid for a non-zero value transfer as part of the CALL operation.
  defmacro _GCALLVALUE do quote do: 9000 end

  # A stipend for the called contract subtracted from Gcallvalue for a
  # non-zero value transfer.
  defmacro _GCALLSTIPEND do quote do: 2300 end

  # Paid for a CALL or SELFDESTRUCT operation which creates an account.
  defmacro _GNEWACCOUNT do quote do: 25000 end

  # Partial payment for an EXP operation.
  defmacro _GEXP do quote do: 10 end

  # Partial payment when multiplied by dlog256(exponent)e for the EXP
  # operation.
  defmacro _GEXPBYTE do quote do: 10 end # From the go implementation. 50 from the yellopaper

  # Paid for every additional word when expanding memory.
  defmacro _GMEMORY do quote do: 3 end

  # Paid by all contract-creating transactions after the Homestead
  # transition.
  defmacro _GTXCREATE do quote do: 32000 end

  # Paid for every zero byte of data or code for a transaction.
  defmacro _GTXDATAZERO do quote do: 4 end

  # Paid for every non-zero byte of data or code for a transaction.
  defmacro _GTXDATANONZERO do quote do: 68 end

  # Paid for every transaction.
  defmacro _GTRANSACTION do quote do: 21000 end

  # Partial payment for a LOG operation.
  defmacro _GLOG do quote do: 375 end

  # Paid for each byte in a LOG operation’s data.
  defmacro _GLOGDATA do quote do: 8 end

  # Paid for each topic of a LOG operation.
  defmacro _GLOGTOPIC do quote do: 375 end

  # Paid for each SHA3 operation.
  defmacro _GSHA3 do quote do: 30 end

  # Paid for each word (rounded up) for input data to a SHA3 operation.
  defmacro _GSHA3WORD do quote do: 6 end

  # Partial payment for *COPY operations, multiplied by words copied,
  # rounded up.
  defmacro _GCOPY do quote do: 3 end

  # Payment for BLOCKHASH operation.
  defmacro _GBLOCKHASH do quote do: 20 end

end
