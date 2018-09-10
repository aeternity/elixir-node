defmodule OpCodesUtil do
  @moduledoc """
  Module containing mnemonics and utils for the OpCodes
  """

  # credo:disable-for-this-file

  require OpCodes
  require GasCodes

  def mnemonic(OpCodes._STOP) do "STOP" end
  def mnemonic(OpCodes._ADD) do "ADD" end
  def mnemonic(OpCodes._MUL) do "MUL" end
  def mnemonic(OpCodes._SUB) do "SUB" end
  def mnemonic(OpCodes._DIV) do "DIV" end
  def mnemonic(OpCodes._SDIV) do "SDIV" end
  def mnemonic(OpCodes._MOD) do "MOD" end
  def mnemonic(OpCodes._SMOD) do "SMOD" end
  def mnemonic(OpCodes._ADDMOD) do "ADDMOD" end
  def mnemonic(OpCodes._MULMOD) do "MULMOD" end
  def mnemonic(OpCodes._EXP) do "EXP" end
  def mnemonic(OpCodes._SIGNEXTEND) do "SIGNEXTEND" end
  def mnemonic(OpCodes._LT) do "LT" end
  def mnemonic(OpCodes._GT) do "GT" end
  def mnemonic(OpCodes._SLT) do "SLT" end
  def mnemonic(OpCodes._SGT) do "SGT" end
  def mnemonic(OpCodes._EQ) do "EQ" end
  def mnemonic(OpCodes._ISZERO) do "ISZERO" end
  def mnemonic(OpCodes._AND) do "AND" end
  def mnemonic(OpCodes._OR) do "OR" end
  def mnemonic(OpCodes._XOR) do "XOR" end
  def mnemonic(OpCodes._NOT) do "NOT" end
  def mnemonic(OpCodes._BYTE) do "BYTE" end
  def mnemonic(OpCodes._SHA3) do "SHA3" end
  def mnemonic(OpCodes._ADDRESS) do "ADDRESS" end
  def mnemonic(OpCodes._BALANCE) do "BALANCE" end
  def mnemonic(OpCodes._ORIGIN) do "ORIGIN" end
  def mnemonic(OpCodes._CALLER) do "CALLER" end
  def mnemonic(OpCodes._CALLVALUE) do "CALLVALUE" end
  def mnemonic(OpCodes._CALLDATALOAD) do "CALLDATALOAD" end
  def mnemonic(OpCodes._CALLDATASIZE) do "CALLDATASIZE" end
  def mnemonic(OpCodes._CALLDATACOPY) do "CALLDATACOPY" end
  def mnemonic(OpCodes._CODESIZE) do "CODESIZE" end
  def mnemonic(OpCodes._CODECOPY) do "CODECOPY" end
  def mnemonic(OpCodes._GASPRICE) do "GASPRICE" end
  def mnemonic(OpCodes._EXTCODESIZE) do "EXTCODESIZE" end
  def mnemonic(OpCodes._EXTCODECOPY) do "EXTCODECOPY" end
  def mnemonic(OpCodes._RETURNDATASIZE) do "RETURNDATASIZE" end
  def mnemonic(OpCodes._RETURNDATACOPY) do "RETURNDATACOPY" end
  def mnemonic(OpCodes._BLOCKHASH) do "BLOCKHASH" end
  def mnemonic(OpCodes._COINBASE) do "COINBASE" end
  def mnemonic(OpCodes._TIMESTAMP) do "TIMESTAMP" end
  def mnemonic(OpCodes._NUMBER) do "NUMBER" end
  def mnemonic(OpCodes._DIFFICULTY) do "DIFFICULTY" end
  def mnemonic(OpCodes._GASLIMIT) do "GASLIMIT" end
  def mnemonic(OpCodes._POP) do "POP" end
  def mnemonic(OpCodes._MLOAD) do "MLOAD" end
  def mnemonic(OpCodes._MSTORE) do "MSTORE" end
  def mnemonic(OpCodes._MSTORE8) do "MSTORE8" end
  def mnemonic(OpCodes._SLOAD) do "SLOAD" end
  def mnemonic(OpCodes._SSTORE) do "SSTORE" end
  def mnemonic(OpCodes._JUMP) do "JUMP" end
  def mnemonic(OpCodes._JUMPI) do "JUMPI" end
  def mnemonic(OpCodes._PC) do "PC" end
  def mnemonic(OpCodes._MSIZE) do "MSIZE" end
  def mnemonic(OpCodes._GAS) do "GAS" end
  def mnemonic(OpCodes._JUMPDEST) do "JUMPDEST" end
  def mnemonic(OpCodes._PUSH1) do "PUSH1" end
  def mnemonic(OpCodes._PUSH2) do "PUSH2" end
  def mnemonic(OpCodes._PUSH3) do "PUSH3" end
  def mnemonic(OpCodes._PUSH4) do "PUSH4" end
  def mnemonic(OpCodes._PUSH5) do "PUSH5" end
  def mnemonic(OpCodes._PUSH6) do "PUSH6" end
  def mnemonic(OpCodes._PUSH7) do "PUSH7" end
  def mnemonic(OpCodes._PUSH8) do "PUSH8" end
  def mnemonic(OpCodes._PUSH9) do "PUSH9" end
  def mnemonic(OpCodes._PUSH10) do "PUSH10" end
  def mnemonic(OpCodes._PUSH11) do "PUSH11" end
  def mnemonic(OpCodes._PUSH12) do "PUSH12" end
  def mnemonic(OpCodes._PUSH13) do "PUSH13" end
  def mnemonic(OpCodes._PUSH14) do "PUSH14" end
  def mnemonic(OpCodes._PUSH15) do "PUSH15" end
  def mnemonic(OpCodes._PUSH16) do "PUSH16" end
  def mnemonic(OpCodes._PUSH17) do "PUSH17" end
  def mnemonic(OpCodes._PUSH18) do "PUSH18" end
  def mnemonic(OpCodes._PUSH19) do "PUSH19" end
  def mnemonic(OpCodes._PUSH20) do "PUSH20" end
  def mnemonic(OpCodes._PUSH21) do "PUSH21" end
  def mnemonic(OpCodes._PUSH22) do "PUSH22" end
  def mnemonic(OpCodes._PUSH23) do "PUSH23" end
  def mnemonic(OpCodes._PUSH24) do "PUSH24" end
  def mnemonic(OpCodes._PUSH25) do "PUSH25" end
  def mnemonic(OpCodes._PUSH26) do "PUSH26" end
  def mnemonic(OpCodes._PUSH27) do "PUSH27" end
  def mnemonic(OpCodes._PUSH28) do "PUSH28" end
  def mnemonic(OpCodes._PUSH29) do "PUSH29" end
  def mnemonic(OpCodes._PUSH30) do "PUSH30" end
  def mnemonic(OpCodes._PUSH31) do "PUSH31" end
  def mnemonic(OpCodes._PUSH32) do "PUSH32" end
  def mnemonic(OpCodes._DUP1) do "DUP1" end
  def mnemonic(OpCodes._DUP2) do "DUP2" end
  def mnemonic(OpCodes._DUP3) do "DUP3" end
  def mnemonic(OpCodes._DUP4) do "DUP4" end
  def mnemonic(OpCodes._DUP5) do "DUP5" end
  def mnemonic(OpCodes._DUP6) do "DUP6" end
  def mnemonic(OpCodes._DUP7) do "DUP7" end
  def mnemonic(OpCodes._DUP8) do "DUP8" end
  def mnemonic(OpCodes._DUP9) do "DUP9" end
  def mnemonic(OpCodes._DUP10) do "DUP10" end
  def mnemonic(OpCodes._DUP11) do "DUP11" end
  def mnemonic(OpCodes._DUP12) do "DUP12" end
  def mnemonic(OpCodes._DUP13) do "DUP13" end
  def mnemonic(OpCodes._DUP14) do "DUP14" end
  def mnemonic(OpCodes._DUP15) do "DUP15" end
  def mnemonic(OpCodes._DUP16) do "DUP16" end
  def mnemonic(OpCodes._SWAP1) do "SWAP1" end
  def mnemonic(OpCodes._SWAP2) do "SWAP2" end
  def mnemonic(OpCodes._SWAP3) do "SWAP3" end
  def mnemonic(OpCodes._SWAP4) do "SWAP4" end
  def mnemonic(OpCodes._SWAP5) do "SWAP5" end
  def mnemonic(OpCodes._SWAP6) do "SWAP6" end
  def mnemonic(OpCodes._SWAP7) do "SWAP7" end
  def mnemonic(OpCodes._SWAP8) do "SWAP8" end
  def mnemonic(OpCodes._SWAP9) do "SWAP9" end
  def mnemonic(OpCodes._SWAP10) do "SWAP10" end
  def mnemonic(OpCodes._SWAP11) do "SWAP11" end
  def mnemonic(OpCodes._SWAP12) do "SWAP12" end
  def mnemonic(OpCodes._SWAP13) do "SWAP13" end
  def mnemonic(OpCodes._SWAP14) do "SWAP14" end
  def mnemonic(OpCodes._SWAP15) do "SWAP15" end
  def mnemonic(OpCodes._SWAP16) do "SWAP16" end
  def mnemonic(OpCodes._LOG0) do "LOG0" end
  def mnemonic(OpCodes._LOG1) do "LOG1" end
  def mnemonic(OpCodes._LOG2) do "LOG2" end
  def mnemonic(OpCodes._LOG3) do "LOG3" end
  def mnemonic(OpCodes._LOG4) do "LOG4" end
  def mnemonic(OpCodes._CREATE) do "CREATE" end
  def mnemonic(OpCodes._CALL) do "CALL" end
  def mnemonic(OpCodes._CALLCODE) do "CALLCODE" end
  def mnemonic(OpCodes._RETURN) do "RETURN" end
  def mnemonic(OpCodes._DELEGATECALL) do "DELEGATECALL" end
  def mnemonic(OpCodes._CALLBLACKBOX) do "CALLBLACKBOX" end
  def mnemonic(OpCodes._STATICCALL) do "STATICCALL" end
  def mnemonic(OpCodes._REVERT) do "REVERT" end
  def mnemonic(OpCodes._INVALID) do "INVALID" end
  def mnemonic(OpCodes._SUICIDE) do "SUICIDE" end

  # {op_code_number, elements_pushed_to_the_stack, elements_popped_from_the_stack, gas_cost}
  def opcode(OpCodes._STOP) do {mnemonic(OpCodes._STOP), 0, 0, GasCodes._GZERO} end
  def opcode(OpCodes._ADD) do {mnemonic(OpCodes._ADD), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._MUL) do {mnemonic(OpCodes._MUL), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._SUB) do {mnemonic(OpCodes._SUB), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DIV) do {mnemonic(OpCodes._DIV), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._SDIV) do {mnemonic(OpCodes._SDIV), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._MOD) do {mnemonic(OpCodes._MOD), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._SMOD) do {mnemonic(OpCodes._SMOD), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._ADDMOD) do {mnemonic(OpCodes._ADDMOD), 3, 1, GasCodes._GMID} end
  def opcode(OpCodes._MULMOD) do {mnemonic(OpCodes._MULMOD), 1, 1, GasCodes._GMID} end
  def opcode(OpCodes._EXP) do {mnemonic(OpCodes._EXP), 2, 1, GasCodes._GEXP} end
  def opcode(OpCodes._SIGNEXTEND) do {mnemonic(OpCodes._SIGNEXTEND), 2, 1, GasCodes._GLOW} end
  def opcode(OpCodes._LT) do {mnemonic(OpCodes._LT), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._GT) do {mnemonic(OpCodes._GT), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SLT) do {mnemonic(OpCodes._SLT), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SGT) do {mnemonic(OpCodes._SGT), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._EQ) do {mnemonic(OpCodes._EQ), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._ISZERO) do {mnemonic(OpCodes._ISZERO), 1, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._AND) do {mnemonic(OpCodes._AND), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._OR) do {mnemonic(OpCodes._OR), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._XOR) do {mnemonic(OpCodes._XOR), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._NOT) do {mnemonic(OpCodes._NOT), 1, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._BYTE) do {mnemonic(OpCodes._BYTE), 2, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SHA3) do {mnemonic(OpCodes._SHA3), 2, 1, GasCodes._GSHA3} end
  def opcode(OpCodes._ADDRESS) do {mnemonic(OpCodes._ADDRESS), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._BALANCE) do {mnemonic(OpCodes._BALANCE), 1, 1, GasCodes._GBALANCE} end
  def opcode(OpCodes._ORIGIN) do {mnemonic(OpCodes._ORIGIN), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._CALLER) do {mnemonic(OpCodes._CALLER), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._CALLVALUE) do {mnemonic(OpCodes._CALLVALUE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._CALLDATALOAD) do {mnemonic(OpCodes._CALLDATALOAD), 1, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._CALLDATASIZE) do {mnemonic(OpCodes._CALLDATASIZE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._CALLDATACOPY) do {mnemonic(OpCodes._CALLDATACOPY), 3, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._CODESIZE) do {mnemonic(OpCodes._CODESIZE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._CODECOPY) do {mnemonic(OpCodes._CODECOPY), 3, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._GASPRICE) do {mnemonic(OpCodes._GASPRICE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._EXTCODESIZE) do {mnemonic(OpCodes._EXTCODESIZE), 1, 1, GasCodes._GEXTCODESIZE} end
  def opcode(OpCodes._EXTCODECOPY) do {mnemonic(OpCodes._EXTCODECOPY), 4, 0, GasCodes._GEXTCODECOPY} end
  def opcode(OpCodes._RETURNDATASIZE) do {mnemonic(OpCodes._RETURNDATASIZE), 0, 1, 2} end
  def opcode(OpCodes._RETURNDATACOPY) do {mnemonic(OpCodes._RETURNDATACOPY), 3, 0, 3} end
  def opcode(OpCodes._BLOCKHASH) do {mnemonic(OpCodes._BLOCKHASH), 1, 1, GasCodes._GBLOCKHASH} end
  def opcode(OpCodes._COINBASE) do {mnemonic(OpCodes._COINBASE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._TIMESTAMP) do {mnemonic(OpCodes._TIMESTAMP), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._NUMBER) do {mnemonic(OpCodes._NUMBER), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._DIFFICULTY) do {mnemonic(OpCodes._DIFFICULTY), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._GASLIMIT) do {mnemonic(OpCodes._GASLIMIT), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._POP) do {mnemonic(OpCodes._POP), 1, 0, GasCodes._GBASE} end
  def opcode(OpCodes._MLOAD) do {mnemonic(OpCodes._MLOAD), 1, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._MSTORE) do {mnemonic(OpCodes._MSTORE), 2, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._MSTORE8) do {mnemonic(OpCodes._MSTORE8), 2, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SLOAD) do {mnemonic(OpCodes._SLOAD), 1, 0, GasCodes._GSLOAD} end
  def opcode(OpCodes._SSTORE) do {mnemonic(OpCodes._SSTORE), 2, 0, 0} end
  def opcode(OpCodes._JUMP) do {mnemonic(OpCodes._JUMP), 1, 0, GasCodes._GMID} end
  def opcode(OpCodes._JUMPI) do {mnemonic(OpCodes._JUMPI), 2, 0, GasCodes._GHIGH} end
  def opcode(OpCodes._PC) do {mnemonic(OpCodes._PC), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._MSIZE) do {mnemonic(OpCodes._MSIZE), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._GAS) do {mnemonic(OpCodes._GAS), 0, 1, GasCodes._GBASE} end
  def opcode(OpCodes._JUMPDEST) do {mnemonic(OpCodes._JUMPDEST), 0, 0, GasCodes._GJUMPDEST} end
  def opcode(OpCodes._PUSH1) do {mnemonic(OpCodes._PUSH1), 1, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH2) do {mnemonic(OpCodes._PUSH2), 2, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH3) do {mnemonic(OpCodes._PUSH3), 3, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH4) do {mnemonic(OpCodes._PUSH4), 4, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH5) do {mnemonic(OpCodes._PUSH5), 5, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH6) do {mnemonic(OpCodes._PUSH6), 6, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH7) do {mnemonic(OpCodes._PUSH7), 7, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH8) do {mnemonic(OpCodes._PUSH8), 8, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH9) do {mnemonic(OpCodes._PUSH9), 9, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH10) do {mnemonic(OpCodes._PUSH10), 10, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH11) do {mnemonic(OpCodes._PUSH11), 11, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH12) do {mnemonic(OpCodes._PUSH12), 12, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH13) do {mnemonic(OpCodes._PUSH13), 13, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH14) do {mnemonic(OpCodes._PUSH14), 14, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH15) do {mnemonic(OpCodes._PUSH15), 15, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH16) do {mnemonic(OpCodes._PUSH16), 16, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH17) do {mnemonic(OpCodes._PUSH17), 17, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH18) do {mnemonic(OpCodes._PUSH18), 18, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH19) do {mnemonic(OpCodes._PUSH19), 19, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH20) do {mnemonic(OpCodes._PUSH20), 20, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH21) do {mnemonic(OpCodes._PUSH21), 21, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH22) do {mnemonic(OpCodes._PUSH22), 22, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH23) do {mnemonic(OpCodes._PUSH23), 23, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH24) do {mnemonic(OpCodes._PUSH24), 24, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH25) do {mnemonic(OpCodes._PUSH25), 25, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH26) do {mnemonic(OpCodes._PUSH26), 26, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH27) do {mnemonic(OpCodes._PUSH27), 27, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH28) do {mnemonic(OpCodes._PUSH28), 28, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH29) do {mnemonic(OpCodes._PUSH29), 29, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH30) do {mnemonic(OpCodes._PUSH30), 30, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH31) do {mnemonic(OpCodes._PUSH31), 31, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._PUSH32) do {mnemonic(OpCodes._PUSH32), 32, 0, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP1) do {mnemonic(OpCodes._DUP1), 0, 1, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP2) do {mnemonic(OpCodes._DUP2), 0, 2, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP3) do {mnemonic(OpCodes._DUP3), 0, 3, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP4) do {mnemonic(OpCodes._DUP4), 0, 4, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP5) do {mnemonic(OpCodes._DUP5), 0, 5, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP6) do {mnemonic(OpCodes._DUP6), 0, 6, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP7) do {mnemonic(OpCodes._DUP7), 0, 7, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP8) do {mnemonic(OpCodes._DUP8), 0, 8, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP9) do {mnemonic(OpCodes._DUP9), 0, 9, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP10) do {mnemonic(OpCodes._DUP10), 0, 10, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP11) do {mnemonic(OpCodes._DUP11), 0, 11, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP12) do {mnemonic(OpCodes._DUP12), 0, 12, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP13) do {mnemonic(OpCodes._DUP13), 0, 13, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP14) do {mnemonic(OpCodes._DUP14), 0, 14, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP15) do {mnemonic(OpCodes._DUP15), 0, 15, GasCodes._GVERYLOW} end
  def opcode(OpCodes._DUP16) do {mnemonic(OpCodes._DUP16), 0, 16, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP1) do {mnemonic(OpCodes._SWAP1), 0, 2, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP2) do {mnemonic(OpCodes._SWAP2), 0, 3, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP3) do {mnemonic(OpCodes._SWAP3), 0, 4, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP4) do {mnemonic(OpCodes._SWAP4), 0, 5, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP5) do {mnemonic(OpCodes._SWAP5), 0, 6, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP6) do {mnemonic(OpCodes._SWAP6), 0, 7, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP7) do {mnemonic(OpCodes._SWAP7), 0, 8, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP8) do {mnemonic(OpCodes._SWAP8), 0, 9, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP9) do {mnemonic(OpCodes._SWAP9), 0, 10, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP10) do {mnemonic(OpCodes._SWAP10), 0, 11, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP11) do {mnemonic(OpCodes._SWAP11), 0, 12, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP12) do {mnemonic(OpCodes._SWAP12), 0, 13, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP13) do {mnemonic(OpCodes._SWAP13), 0, 14, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP14) do {mnemonic(OpCodes._SWAP14), 0, 15, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP15) do {mnemonic(OpCodes._SWAP15), 0, 16, GasCodes._GVERYLOW} end
  def opcode(OpCodes._SWAP16) do {mnemonic(OpCodes._SWAP16), 0, 17, GasCodes._GVERYLOW} end
  def opcode(OpCodes._LOG0) do {mnemonic(OpCodes._LOG0), 2, 0, GasCodes._GLOG} end
  def opcode(OpCodes._LOG1) do {mnemonic(OpCodes._LOG1), 3, 0, GasCodes._GLOG + GasCodes._GLOGTOPIC} end
  def opcode(OpCodes._LOG2) do {mnemonic(OpCodes._LOG2), 4, 0, GasCodes._GLOG + 2 * GasCodes._GLOGTOPIC} end
  def opcode(OpCodes._LOG3) do {mnemonic(OpCodes._LOG3), 5, 0, GasCodes._GLOG + 3 * GasCodes._GLOGTOPIC} end
  def opcode(OpCodes._LOG4) do {mnemonic(OpCodes._LOG4), 6, 0, GasCodes._GLOG + 4 * GasCodes._GLOGTOPIC} end
  def opcode(OpCodes._CREATE) do {mnemonic(OpCodes._CREATE), 3, 1, GasCodes._GCREATE} end
  def opcode(OpCodes._CALL) do {mnemonic(OpCodes._CALL), 7, 1, 0} end
  def opcode(OpCodes._CALLCODE) do {mnemonic(OpCodes._CALLCODE), 7, 1, 0} end
  def opcode(OpCodes._RETURN) do {mnemonic(OpCodes._RETURN), 3, 0, GasCodes._GZERO} end
  def opcode(OpCodes._DELEGATECALL) do {mnemonic(OpCodes._DELEGATECALL), 6, 1, 0} end
  def opcode(OpCodes._CALLBLACKBOX) do {mnemonic(OpCodes._CALLBLACKBOX), 7, 1, 40} end
  def opcode(OpCodes._STATICCALL) do {mnemonic(OpCodes._STATICCALL), 6, 1, 40} end
  def opcode(OpCodes._REVERT) do {mnemonic(OpCodes._REVERT), 2, 0, 0} end
  def opcode(OpCodes._INVALID) do {mnemonic(OpCodes._INVALID), 0, 0, 0} end
  def opcode(OpCodes._SUICIDE) do {mnemonic(OpCodes._SUICIDE), 1, 0, GasCodes._GSELFDESTRUCT} end

  def op_size(op) when op >= OpCodes._PUSH1 and op <= OpCodes._PUSH32 do
    (op - OpCodes._PUSH1) + 1
  end
  def op_size(_) do
    1
  end

end
