defmodule OpCodes do
  @moduledoc """
  Module containing OpCode macro definitions
  """

  # credo:disable-for-this-file

  # 0s: Stop and Arithmetic Operations
  defmacro _STOP do quote do: 0x00 end
  defmacro _ADD do quote do: 0x01 end
  defmacro _MUL do quote do: 0x02 end
  defmacro _SUB do quote do: 0x03 end
  defmacro _DIV do quote do: 0x04 end
  defmacro _SDIV do quote do: 0x05 end
  defmacro _MOD do quote do: 0x06 end
  defmacro _SMOD do quote do: 0x07 end
  defmacro _ADDMOD do quote do: 0x08 end
  defmacro _MULMOD do quote do: 0x09 end
  defmacro _EXP do quote do: 0x0a end
  defmacro _SIGNEXTEND do quote do: 0x0b end

  # 10s: Comparison & Bitwise Logic Operations

  defmacro _LT do quote do: 0x10 end
  defmacro _GT do quote do: 0x11 end
  defmacro _SLT do quote do: 0x12 end
  defmacro _SGT do quote do: 0x13 end
  defmacro _EQ do quote do: 0x14 end
  defmacro _ISZERO do quote do: 0x15 end
  defmacro _AND do quote do: 0x16 end
  defmacro _OR do quote do: 0x17 end
  defmacro _XOR do quote do: 0x18 end
  defmacro _NOT do quote do: 0x19 end
  defmacro _BYTE do quote do: 0x1a end

  # 20s: SHA3

  defmacro _SHA3 do quote do: 0x20 end

  #30s: Environmental Information

  defmacro _ADDRESS do quote do: 0x30 end
  defmacro _BALANCE do quote do: 0x31 end
  defmacro _ORIGIN do quote do: 0x32 end
  defmacro _CALLER do quote do: 0x33 end
  defmacro _CALLVALUE do quote do: 0x34 end
  defmacro _CALLDATALOAD do quote do: 0x35 end
  defmacro _CALLDATASIZE do quote do: 0x36 end
  defmacro _CALLDATACOPY do quote do: 0x37 end
  defmacro _CODESIZE do quote do: 0x38 end
  defmacro _CODECOPY do quote do: 0x39 end
  defmacro _GASPRICE do quote do: 0x3a end
  defmacro _EXTCODESIZE do quote do: 0x3b end
  defmacro _EXTCODECOPY do quote do: 0x3c end
  defmacro _RETURNDATASIZE do quote do: 0x3d end
  defmacro _RETURNDATACOPY do quote do: 0x3e end

  # 40s: Block Information

  defmacro _BLOCKHASH do quote do: 0x40 end
  defmacro _COINBASE do quote do: 0x41 end
  defmacro _TIMESTAMP do quote do: 0x42 end
  defmacro _NUMBER do quote do: 0x43 end
  defmacro _DIFFICULTY do quote do: 0x44 end
  defmacro _GASLIMIT do quote do: 0x45 end

  # 50s: Stack, Memory, Storage and Flow Operations

  defmacro _POP do quote do: 0x50 end
  defmacro _MLOAD do quote do: 0x51 end
  defmacro _MSTORE do quote do: 0x52 end
  defmacro _MSTORE8 do quote do: 0x53 end
  defmacro _SLOAD do quote do: 0x54 end
  defmacro _SSTORE do quote do: 0x55 end
  defmacro _JUMP do quote do: 0x56 end
  defmacro _JUMPI do quote do: 0x57 end
  defmacro _PC do quote do: 0x58 end
  defmacro _MSIZE do quote do: 0x59 end
  defmacro _GAS do quote do: 0x5a end
  defmacro _JUMPDEST do quote do: 0x5b end

  # 60s & 70s: Push Operations_PUSH

  defmacro _PUSH1 do quote do: 0x60 end
  defmacro _PUSH2 do quote do: 0x61 end
  defmacro _PUSH3 do quote do: 0x62 end
  defmacro _PUSH4 do quote do: 0x63 end
  defmacro _PUSH5 do quote do: 0x64 end
  defmacro _PUSH6 do quote do: 0x65 end
  defmacro _PUSH7 do quote do: 0x66 end
  defmacro _PUSH8 do quote do: 0x67 end
  defmacro _PUSH9 do quote do: 0x68 end
  defmacro _PUSH10 do quote do: 0x69 end
  defmacro _PUSH11 do quote do: 0x6a end
  defmacro _PUSH12 do quote do: 0x6b end
  defmacro _PUSH13 do quote do: 0x6c end
  defmacro _PUSH14 do quote do: 0x6d end
  defmacro _PUSH15 do quote do: 0x6e end
  defmacro _PUSH16 do quote do: 0x6f end
  defmacro _PUSH17 do quote do: 0x70 end
  defmacro _PUSH18 do quote do: 0x71 end
  defmacro _PUSH19 do quote do: 0x72 end
  defmacro _PUSH20 do quote do: 0x73 end
  defmacro _PUSH21 do quote do: 0x74 end
  defmacro _PUSH22 do quote do: 0x75 end
  defmacro _PUSH23 do quote do: 0x76 end
  defmacro _PUSH24 do quote do: 0x77 end
  defmacro _PUSH25 do quote do: 0x78 end
  defmacro _PUSH26 do quote do: 0x79 end
  defmacro _PUSH27 do quote do: 0x7a end
  defmacro _PUSH28 do quote do: 0x7b end
  defmacro _PUSH29 do quote do: 0x7c end
  defmacro _PUSH30 do quote do: 0x7d end
  defmacro _PUSH31 do quote do: 0x7e end
  defmacro _PUSH32 do quote do: 0x7f end

  # 80s: Duplication Operations

  defmacro _DUP1 do quote do: 0x80 end
  defmacro _DUP2 do quote do: 0x81 end
  defmacro _DUP3 do quote do: 0x82 end
  defmacro _DUP4 do quote do: 0x83 end
  defmacro _DUP5 do quote do: 0x84 end
  defmacro _DUP6 do quote do: 0x85 end
  defmacro _DUP7 do quote do: 0x86 end
  defmacro _DUP8 do quote do: 0x87 end
  defmacro _DUP9 do quote do: 0x88 end
  defmacro _DUP10 do quote do: 0x89 end
  defmacro _DUP11 do quote do: 0x8a end
  defmacro _DUP12 do quote do: 0x8b end
  defmacro _DUP13 do quote do: 0x8c end
  defmacro _DUP14 do quote do: 0x8d end
  defmacro _DUP15 do quote do: 0x8e end
  defmacro _DUP16 do quote do: 0x8f end

  # 90s: Exchange Operations

  defmacro _SWAP1 do quote do: 0x90 end
  defmacro _SWAP2 do quote do: 0x91 end
  defmacro _SWAP3 do quote do: 0x92 end
  defmacro _SWAP4 do quote do: 0x93 end
  defmacro _SWAP5 do quote do: 0x94 end
  defmacro _SWAP6 do quote do: 0x95 end
  defmacro _SWAP7 do quote do: 0x96 end
  defmacro _SWAP8 do quote do: 0x97 end
  defmacro _SWAP9 do quote do: 0x98 end
  defmacro _SWAP10 do quote do: 0x99 end
  defmacro _SWAP11 do quote do: 0x9a end
  defmacro _SWAP12 do quote do: 0x9b end
  defmacro _SWAP13 do quote do: 0x9c end
  defmacro _SWAP14 do quote do: 0x9d end
  defmacro _SWAP15 do quote do: 0x9e end
  defmacro _SWAP16 do quote do: 0x9f end

  # a0s: Logging Operations

  defmacro _LOG0 do quote do: 0xa0 end
  defmacro _LOG1 do quote do: 0xa1 end
  defmacro _LOG2 do quote do: 0xa2 end
  defmacro _LOG3 do quote do: 0xa3 end
  defmacro _LOG4 do quote do: 0xa4 end

  # f0s: System operations

  defmacro _CREATE do quote do: 0xf0 end
  defmacro _CALL do quote do: 0xf1 end
  defmacro _CALLCODE do quote do: 0xf2 end
  defmacro _RETURN do quote do: 0xf3 end
  defmacro _DELEGATECALL do quote do: 0xf4 end
  defmacro _CALLBLACKBOX do quote do: 0xf5 end
  defmacro _STATICCALL do quote do: 0xfa end
  defmacro _REVERT do quote do: 0xfd end
  defmacro _INVALID do quote do: 0xfe end

  #Halt Execution, Mark for deletion

  defmacro _SUICIDE do quote do: 0xff end

end
