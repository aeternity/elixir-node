# defmodule AevmTest do
#   use ExUnit.Case
#   use ExUnit.Parameterized

#   require Logger
#   alias Aevm

#   doctest Aevm

#   defp validate_storage(%{:exec => %{:address => address}} = spec, storage_state) do
#     case spec do
#       %{:post => post} ->
#         storage_test =
#           case Map.get(post, address, nil) do
#             nil -> %{}
#             %{:storage => storage} -> storage
#           end

#         assert storage_test == storage_state

#       _ ->
#         true
#     end
#   end

#   defp validate_out(out_test, out_state) do
#     assert out_test == out_state
#   end

#   defp validate_gas(gas_test, gas_state) do
#     assert gas_test == gas_state
#   end

#   defp validate_callcreates(%{:callcreates => callcreates_test}, callcreates_state) do
#     assert callcreates_test == callcreates_state
#   end

#   defp validate_no_post(%{:post => _post} = spec), do: {:should_have_succeeded, spec}
#   defp validate_no_post(%{}), do: :ok

#   defp test_opts do
#     %{
#       :execute_calls => false
#     }
#   end

#   defp extract_and_validate(json_test, config_name) do
#     spec = Map.get(json_test, config_name)

#     exec_values = Map.get(spec, :exec)
#     env_values = Map.get(spec, :env)
#     pre_values = Map.get(spec, :pre)

#     try do
#       {:ok, state} = Aevm.loop(State.init_vm(exec_values, env_values, pre_values, 0, test_opts()))

#       validate_storage(spec, state.storage)
#       validate_gas(spec.gas, state.gas)
#       validate_out(spec.out, state.out)
#       validate_callcreates(spec, state.callcreates)

#       {:ok, state}
#     catch
#       {:error, _reason, state} ->
#         validate_no_post(spec)

#         {:error, state}
#     end
#   end

#   test_with_params "vmArithmeticTest1", fn config_name ->
#     json_test = load_test_config(:vmArithmeticTest, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:add0},
#       {:add1},
#       {:add2},
#       {:add3},
#       {:add4},
#       {:addmod0},
#       {:addmod1},
#       {:addmod1_overflow2},
#       {:addmod1_overflow3},
#       {:addmod1_overflow4},
#       {:addmod1_overflowDiff},
#       {:addmod2},
#       {:addmod2_0},
#       {:addmod2_1},
#       {:addmod3},
#       {:addmod3_0},
#       {:addmodBigIntCast},
#       {:addmodDivByZero},
#       {:addmodDivByZero1},
#       {:addmodDivByZero2},
#       {:addmodDivByZero3},
#       {:arith1},
#       {:div1},
#       {:divBoostBug},
#       {:divByNonZero0},
#       {:divByNonZero1},
#       {:divByNonZero2},
#       {:divByNonZero3},
#       {:divByZero},
#       {:divByZero_2},
#       {:exp0},
#       {:exp1},
#       {:exp2},
#       {:exp3},
#       {:exp4},
#       {:exp5},
#       {:exp6},
#       {:exp7},
#       {:expPowerOf256Of256_0},
#       {:expPowerOf256Of256_1},
#       {:expPowerOf256Of256_10},
#       {:expPowerOf256Of256_11},
#       {:expPowerOf256Of256_12},
#       {:expPowerOf256Of256_13},
#       {:expPowerOf256Of256_14},
#       {:expPowerOf256Of256_15},
#       {:expPowerOf256Of256_16},
#       {:expPowerOf256Of256_17},
#       {:expPowerOf256Of256_18},
#       {:expPowerOf256Of256_19},
#       {:expPowerOf256Of256_2},
#       {:expPowerOf256Of256_20},
#       {:expPowerOf256Of256_21},
#       {:expPowerOf256Of256_22},
#       {:expPowerOf256Of256_23},
#       {:expPowerOf256Of256_24},
#       {:expPowerOf256Of256_25},
#       {:expPowerOf256Of256_26},
#       {:expPowerOf256Of256_27},
#       {:expPowerOf256Of256_28},
#       {:expPowerOf256Of256_29},
#       {:expPowerOf256Of256_3},
#       {:expPowerOf256Of256_30},
#       {:expPowerOf256Of256_31},
#       {:expPowerOf256Of256_32},
#       {:expPowerOf256Of256_33},
#       {:expPowerOf256Of256_4},
#       {:expPowerOf256Of256_5},
#       {:expPowerOf256Of256_6},
#       {:expPowerOf256Of256_7},
#       {:expPowerOf256Of256_8},
#       {:expPowerOf256Of256_9},
#       {:expPowerOf256_1},
#       {:expPowerOf256_10},
#       {:expPowerOf256_11},
#       {:expPowerOf256_12},
#       {:expPowerOf256_13},
#       {:expPowerOf256_14},
#       {:expPowerOf256_15},
#       {:expPowerOf256_16},
#       {:expPowerOf256_17},
#       {:expPowerOf256_18},
#       {:expPowerOf256_19},
#       {:expPowerOf256_2},
#       {:expPowerOf256_20},
#       {:expPowerOf256_21},
#       {:expPowerOf256_22},
#       {:expPowerOf256_23},
#       {:expPowerOf256_24},
#       {:expPowerOf256_25},
#       {:expPowerOf256_26},
#       {:expPowerOf256_27},
#       {:expPowerOf256_28},
#       {:expPowerOf256_29},
#       {:expPowerOf256_3},
#       {:expPowerOf256_30},
#       {:expPowerOf256_31},
#       {:expPowerOf256_32},
#       {:expPowerOf256_33},
#       {:expPowerOf256_4},
#       {:expPowerOf256_5},
#       {:expPowerOf256_6},
#       {:expPowerOf256_7},
#       {:expPowerOf256_8},
#       {:expPowerOf256_9},
#       {:expPowerOf2_128},
#       {:expPowerOf2_16},
#       {:expPowerOf2_2},
#       {:expPowerOf2_256},
#       {:expPowerOf2_32},
#       {:expPowerOf2_4},
#       {:expPowerOf2_64},
#       {:expPowerOf2_8},
#       {:expXY},
#       {:expXY_success},
#       {:fibbonacci_unrolled},
#       {:mod0},
#       {:mod1},
#       {:mod2},
#       {:mod3},
#       {:mod4},
#       {:modByZero},
#       {:mul0},
#       {:mul1},
#       {:mul2},
#       {:mul3},
#       {:mul4},
#       {:mul5},
#       {:mul6},
#       {:mul7},
#       {:mulUnderFlow},
#       {:mulmod0},
#       {:mulmod1},
#       {:mulmod1_overflow},
#       {:mulmod1_overflow2},
#       {:mulmod1_overflow3},
#       {:mulmod1_overflow4},
#       {:mulmod2},
#       {:mulmod2_0},
#       {:mulmod2_1},
#       {:mulmod3},
#       {:mulmod3_0},
#       {:mulmod4},
#       {:mulmoddivByZero},
#       {:mulmoddivByZero1},
#       {:mulmoddivByZero2},
#       {:mulmoddivByZero3},
#       {:not1},
#       {:sdiv0},
#       {:sdiv1},
#       {:sdiv2},
#       {:sdiv3},
#       {:sdiv4},
#       {:sdiv5},
#       {:sdiv6},
#       {:sdiv7},
#       {:sdiv8},
#       {:sdiv9},
#       {:sdivByZero0},
#       {:sdivByZero1},
#       {:sdivByZero2},
#       {:sdiv_dejavu},
#       {:sdiv_i256min},
#       {:sdiv_i256min2},
#       {:sdiv_i256min3},
#       {:signextendInvalidByteNumber},
#       {:signextend_00},
#       {:signextend_0_BigByte},
#       {:signextend_AlmostBiggestByte},
#       {:signextend_BigByteBigByte},
#       {:signextend_BigBytePlus1_2},
#       {:signextend_BigByte_0},
#       {:signextend_BitIsNotSet},
#       {:signextend_BitIsNotSetInHigherByte},
#       {:signextend_BitIsSetInHigherByte},
#       # {:signextend_Overflow_dj42}, # not working
#       {:signextend_bigBytePlus1},
#       {:signextend_bitIsSet},
#       {:smod0},
#       {:smod1},
#       {:smod2},
#       {:smod3},
#       {:smod4},
#       {:smod5},
#       {:smod6},
#       {:smod7},
#       {:smod8_byZero},
#       {:smod_i256min1},
#       {:smod_i256min2},
#       {:stop},
#       {:sub0},
#       {:sub1},
#       {:sub2},
#       {:sub3},
#       {:sub4}
#     ]
#   end

#   test_with_params "vmBitwiseLogicOperation1", fn config_name ->
#     json_test = load_test_config(:vmBitwiseLogicOperation, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:and0},
#       {:and1},
#       {:and2},
#       {:and3},
#       {:and4},
#       {:and5},
#       {:byte0},
#       {:byte1},
#       {:byte10},
#       {:byte11},
#       {:byte2},
#       {:byte3},
#       {:byte4},
#       {:byte5},
#       {:byte6},
#       {:byte7},
#       {:byte8},
#       {:byte9},
#       {:eq0},
#       {:eq1},
#       {:eq2},
#       {:gt0},
#       {:gt1},
#       {:gt2},
#       {:gt3},
#       {:iszeo2},
#       {:iszero0},
#       {:iszero1},
#       {:lt0},
#       {:lt1},
#       {:lt2},
#       {:lt3},
#       {:not0},
#       {:not1},
#       {:not2},
#       {:not3},
#       {:not4},
#       {:not5},
#       {:or0},
#       {:or1},
#       {:or2},
#       {:or3},
#       {:or4},
#       {:or5},
#       {:sgt0},
#       {:sgt1},
#       {:sgt2},
#       {:sgt3},
#       {:sgt4},
#       {:slt0},
#       {:slt1},
#       {:slt2},
#       {:slt3},
#       {:slt4},
#       {:xor0},
#       {:xor1},
#       {:xor2},
#       {:xor3},
#       {:xor4},
#       {:xor5}
#     ]
#   end

#   test_with_params "vmBlockInfoTest1", fn config_name ->
#     json_test = load_test_config(:vmBlockInfoTest, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:blockhash257Block},
#       {:blockhash258Block},
#       # {:blockhashInRange},
#       {:blockhashMyBlock},
#       {:blockhashNotExistingBlock},
#       {:blockhashOutOfRange},
#       {:blockhashUnderFlow},
#       {:coinbase},
#       {:difficulty},
#       {:gaslimit},
#       {:number},
#       {:timestamp}
#     ]
#   end

#   test_with_params "vmEnvironmentalInfo1", fn config_name ->
#     json_test = load_test_config(:vmEnvironmentalInfo, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       # {:ExtCodeSizeAddressInputTooBigLeftMyAddress}, #not working
#       {:ExtCodeSizeAddressInputTooBigRightMyAddress},
#       {:address0},
#       {:address1},
#       {:balance0},
#       {:balance01},
#       {:balance1},
#       {:balanceAddress2},
#       {:balanceAddressInputTooBig},
#       # {:balanceAddressInputTooBigLeftMyAddress}, #not working
#       {:balanceAddressInputTooBigRightMyAddress},
#       {:balanceCaller3},
#       {:calldatacopy0},
#       {:calldatacopy0_return},
#       {:calldatacopy1},
#       {:calldatacopy1_return},
#       {:calldatacopy2},
#       {:calldatacopy2_return},
#       {:calldatacopyUnderFlow},
#       {:calldatacopyZeroMemExpansion},
#       {:calldatacopyZeroMemExpansion_return},
#       {:calldatacopy_DataIndexTooHigh},
#       {:calldatacopy_DataIndexTooHigh2},
#       {:calldatacopy_DataIndexTooHigh2_return},
#       {:calldatacopy_DataIndexTooHigh_return},
#       {:calldatacopy_sec},
#       {:calldataload0},
#       {:calldataload1},
#       {:calldataload2},
#       {:calldataloadSizeTooHigh},
#       {:calldataloadSizeTooHighPartial},
#       {:calldataload_BigOffset},
#       {:calldatasize0},
#       {:calldatasize1},
#       {:calldatasize2},
#       {:caller},
#       {:callvalue},
#       {:codecopy0},
#       {:codecopyZeroMemExpansion},
#       {:codecopy_DataIndexTooHigh},
#       {:codesize},
#       # {:env1}, #not working
#       {:extcodecopy0},
#       # {:extcodecopy0AddressTooBigLeft}, #not working
#       {:extcodecopy0AddressTooBigRight},
#       {:extcodecopyZeroMemExpansion},
#       {:extcodecopy_DataIndexTooHigh},
#       {:extcodesize0},
#       {:extcodesize1},
#       {:extcodesizeUnderFlow},
#       {:gasprice},
#       {:origin}
#     ]
#   end

#   test_with_params "vmIOandFlowOperations1", fn config_name ->
#     json_test = load_test_config(:vmIOandFlowOperations, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:BlockNumberDynamicJump0_AfterJumpdest},
#       {:BlockNumberDynamicJump0_AfterJumpdest3},
#       {:BlockNumberDynamicJump0_foreverOutOfGas},
#       {:BlockNumberDynamicJump0_jumpdest0},
#       {:BlockNumberDynamicJump0_jumpdest2},
#       {:BlockNumberDynamicJump0_withoutJumpdest},
#       {:BlockNumberDynamicJump1},
#       {:BlockNumberDynamicJumpInsidePushWithJumpDest},
#       {:BlockNumberDynamicJumpInsidePushWithoutJumpDest},
#       {:BlockNumberDynamicJumpi0},
#       {:BlockNumberDynamicJumpi1},
#       {:BlockNumberDynamicJumpi1_jumpdest},
#       {:BlockNumberDynamicJumpiAfterStop},
#       {:BlockNumberDynamicJumpiOutsideBoundary},
#       {:BlockNumberDynamicJumpifInsidePushWithJumpDest},
#       {:BlockNumberDynamicJumpifInsidePushWithoutJumpDest},
#       {:DyanmicJump0_outOfBoundary},
#       {:DynamicJump0_AfterJumpdest},
#       {:DynamicJump0_AfterJumpdest3},
#       {:DynamicJump0_foreverOutOfGas},
#       {:DynamicJump0_jumpdest0},
#       {:DynamicJump0_jumpdest2},
#       {:DynamicJump0_withoutJumpdest},
#       {:DynamicJump1},
#       {:DynamicJumpAfterStop},
#       {:DynamicJumpInsidePushWithJumpDest},
#       {:DynamicJumpInsidePushWithoutJumpDest},
#       {:DynamicJumpJD_DependsOnJumps0},
#       {:DynamicJumpJD_DependsOnJumps1},
#       {:DynamicJumpPathologicalTest0},
#       {:DynamicJumpPathologicalTest1},
#       {:DynamicJumpPathologicalTest2},
#       {:DynamicJumpPathologicalTest3},
#       {:DynamicJumpStartWithJumpDest},
#       {:DynamicJump_value1},
#       {:DynamicJump_value2},
#       {:DynamicJump_value3},
#       {:DynamicJump_valueUnderflow},
#       {:DynamicJumpi0},
#       {:DynamicJumpi1},
#       {:DynamicJumpi1_jumpdest},
#       {:DynamicJumpiAfterStop},
#       {:DynamicJumpiOutsideBoundary},
#       {:DynamicJumpifInsidePushWithJumpDest},
#       {:DynamicJumpifInsidePushWithoutJumpDest},
#       {:JDfromStorageDynamicJump0_AfterJumpdest},
#       {:JDfromStorageDynamicJump0_AfterJumpdest3},
#       {:JDfromStorageDynamicJump0_foreverOutOfGas},
#       {:JDfromStorageDynamicJump0_jumpdest0},
#       {:JDfromStorageDynamicJump0_jumpdest2},
#       {:JDfromStorageDynamicJump0_withoutJumpdest},
#       {:JDfromStorageDynamicJump1},
#       {:JDfromStorageDynamicJumpInsidePushWithJumpDest},
#       {:JDfromStorageDynamicJumpInsidePushWithoutJumpDest},
#       {:JDfromStorageDynamicJumpi0},
#       {:JDfromStorageDynamicJumpi1},
#       {:JDfromStorageDynamicJumpi1_jumpdest},
#       {:JDfromStorageDynamicJumpiAfterStop},
#       {:JDfromStorageDynamicJumpiOutsideBoundary},
#       {:JDfromStorageDynamicJumpifInsidePushWithJumpDest},
#       {:JDfromStorageDynamicJumpifInsidePushWithoutJumpDest},
#       {:bad_indirect_jump1},
#       {:bad_indirect_jump2},
#       {:byte1},
#       {:calldatacopyMemExp},
#       {:codecopyMemExp},
#       {:deadCode_1},
#       {:dupAt51becameMload},
#       {:extcodecopyMemExp},
#       {:for_loop1},
#       {:for_loop2},
#       {:gas0},
#       {:gas1},
#       {:gasOverFlow},
#       {:indirect_jump1},
#       {:indirect_jump2},
#       {:indirect_jump3},
#       {:indirect_jump4},
#       {:jump0_AfterJumpdest},
#       {:jump0_AfterJumpdest3},
#       {:jump0_foreverOutOfGas},
#       {:jump0_jumpdest0},
#       {:jump0_jumpdest2},
#       {:jump0_outOfBoundary},
#       {:jump0_withoutJumpdest},
#       {:jump1},
#       {:jumpAfterStop},
#       {:jumpDynamicJumpSameDest},
#       {:jumpHigh},
#       {:jumpInsidePushWithJumpDest},
#       {:jumpInsidePushWithoutJumpDest},
#       {:jumpOntoJump},
#       {:jumpTo1InstructionafterJump},
#       {:jumpTo1InstructionafterJump_jumpdestFirstInstruction},
#       {:jumpTo1InstructionafterJump_noJumpDest},
#       {:jumpToUint64maxPlus1},
#       {:jumpToUintmaxPlus1},
#       {:jumpdestBigList},
#       {:jumpi0},
#       {:jumpi1},
#       {:jumpi1_jumpdest},
#       {:jumpiAfterStop},
#       {:jumpiOutsideBoundary},
#       {:jumpiToUint64maxPlus1},
#       {:jumpiToUintmaxPlus1},
#       {:jumpi_at_the_end},
#       {:jumpifInsidePushWithJumpDest},
#       {:jumpifInsidePushWithoutJumpDest},
#       {:kv1},
#       {:log1MemExp},
#       {:loop_stacklimit_1020},
#       {:loop_stacklimit_1021},
#       {:memory1},
#       {:mloadError0},
#       {:mloadError1},
#       {:mloadMemExp},
#       {:mloadOutOfGasError2},
#       {:msize0},
#       {:msize1},
#       {:msize2},
#       {:msize3},
#       {:mstore0},
#       {:mstore1},
#       {:mstore8MemExp},
#       {:mstore8WordToBigError},
#       {:mstore8_0},
#       {:mstore8_1},
#       {:mstoreMemExp},
#       {:mstoreWordToBigError},
#       {:mstore_mload0},
#       {:pc0},
#       {:pc1},
#       {:pop0},
#       {:pop1},
#       {:return1},
#       {:return2},
#       {:sha3MemExp},
#       {:sstore_load_0},
#       {:sstore_load_1},
#       {:sstore_load_2},
#       {:sstore_underflow},
#       {:stack_loop},
#       {:stackjump1},
#       {:swapAt52becameMstore},
#       {:when}
#     ]
#   end

#   test_with_params "vmLogTest1", fn config_name ->
#     json_test = load_test_config(:vmLogTest, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:log0_emptyMem},
#       # {:log0_logMemStartTooHigh}, #not working
#       # {:log0_logMemsizeTooHigh}, #not working
#       {:log0_logMemsizeZero},
#       {:log0_nonEmptyMem},
#       {:log0_nonEmptyMem_logMemSize1},
#       {:log0_nonEmptyMem_logMemSize1_logMemStart31},
#       {:log1_Caller},
#       {:log1_MaxTopic},
#       {:log1_emptyMem},
#       # {:log1_logMemStartTooHigh}, #not working
#       # {:log1_logMemsizeTooHigh}, #not working
#       {:log1_logMemsizeZero},
#       {:log1_nonEmptyMem},
#       {:log1_nonEmptyMem_logMemSize1},
#       {:log1_nonEmptyMem_logMemSize1_logMemStart31},
#       {:log2_Caller},
#       {:log2_MaxTopic},
#       {:log2_emptyMem},
#       # {:log2_logMemStartTooHigh}, #not working
#       # {:log2_logMemsizeTooHigh}, #not working
#       {:log2_logMemsizeZero},
#       {:log2_nonEmptyMem},
#       {:log2_nonEmptyMem_logMemSize1},
#       {:log2_nonEmptyMem_logMemSize1_logMemStart31},
#       {:log3_Caller},
#       {:log3_MaxTopic},
#       {:log3_PC},
#       {:log3_emptyMem},
#       # {:log3_logMemStartTooHigh}, #not working
#       # {:log3_logMemsizeTooHigh}, #not working
#       {:log3_logMemsizeZero},
#       {:log3_nonEmptyMem},
#       {:log3_nonEmptyMem_logMemSize1},
#       {:log3_nonEmptyMem_logMemSize1_logMemStart31},
#       {:log4_Caller},
#       {:log4_MaxTopic},
#       {:log4_PC},
#       {:log4_emptyMem},
#       # {:log4_logMemStartTooHigh}, TODO:binary_alloc: Cannot reallocate 4831838237 bytes of memory
#       # {:log4_logMemsizeTooHigh}, #not working
#       {:log4_logMemsizeZero},
#       {:log4_nonEmptyMem},
#       {:log4_nonEmptyMem_logMemSize1},
#       {:log4_nonEmptyMem_logMemSize1_logMemStart31},
#       {:log_2logs}
#     ]
#   end

#   test_with_params "vmPerformance1", fn config_name ->
#     json_test = load_test_config(:vmPerformance, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       # {:ackermann31},
#       # {:ackermann32},
#       # {:ackermann33},
#       # {:fibonacci10},
#       # {:fibonacci16},
#       # {:"loop-add-10M"},
#       # {:"loop-divadd-10M"},
#       # {:"loop-divadd-unr100-10M"},
#       # {:"loop-exp-16b-100k"},
#       # {:"loop-exp-1b-1M"},
#       # {:"loop-exp-2b-100k"},
#       # {:"loop-exp-32b-100k"},
#       # {:"loop-exp-4b-100k"},
#       # {:"loop-exp-8b-100k"},
#       # {:"loop-exp-nop-1M"},
#       # {:"loop-mul"},
#       # {:"loop-mulmod-2M"},
#       # {:manyFunctions100}
#     ]
#   end

#   test_with_params "vmPushDupSwapTest1", fn config_name ->
#     json_test = load_test_config(:vmPushDupSwapTest, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:dup1},
#       {:dup10},
#       {:dup11},
#       {:dup12},
#       {:dup13},
#       {:dup14},
#       {:dup15},
#       {:dup16},
#       {:dup2},
#       {:dup2error},
#       {:dup3},
#       {:dup4},
#       {:dup5},
#       {:dup6},
#       {:dup7},
#       {:dup8},
#       {:dup9},
#       {:push1},
#       {:push10},
#       {:push11},
#       {:push12},
#       {:push13},
#       {:push14},
#       {:push15},
#       {:push16},
#       {:push17},
#       {:push18},
#       {:push19},
#       {:push1_missingStack},
#       {:push2},
#       {:push20},
#       {:push21},
#       {:push22},
#       {:push23},
#       {:push24},
#       {:push25},
#       {:push26},
#       {:push27},
#       {:push28},
#       {:push29},
#       {:push3},
#       {:push30},
#       {:push31},
#       {:push32},
#       # {:push32AndSuicide}, # not working
#       {:push32FillUpInputWithZerosAtTheEnd},
#       {:push32Undefined},
#       {:push32Undefined2},
#       {:push32Undefined3},
#       {:push33},
#       {:push4},
#       {:push5},
#       {:push6},
#       {:push7},
#       {:push8},
#       {:push9},
#       {:swap1},
#       {:swap10},
#       {:swap11},
#       {:swap12},
#       {:swap13},
#       {:swap14},
#       {:swap15},
#       {:swap16},
#       {:swap2},
#       {:swap2error},
#       {:swap3},
#       {:swap4},
#       {:swap5},
#       {:swap6},
#       {:swap7},
#       {:swap8},
#       {:swap9},
#       {:swapjump1}
#     ]
#   end

#   test_with_params "vmRandomTest1", fn config_name ->
#     json_test = load_test_config(:vmRandomTest, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       # {:"201503102037PYTHON"}, # not working
#       # {:"201503102148PYTHON"}, # not working
#       # {:"201503102300PYTHON"}, # not working
#       {:"201503102320PYTHON"},
#       # {:"201503110050PYTHON"}, # not working
#       {:"201503110206PYTHON"},
#       {:"201503110219PYTHON"},
#       {:"201503110346PYTHON_PUSH24"},
#       {:"201503110526PYTHON"},
#       {:"201503111844PYTHON"},
#       {:"201503112218PYTHON"},
#       {:"201503120317PYTHON"},
#       {:"201503120525PYTHON"},
#       {:"201503120547PYTHON"},
#       {:"201503120909PYTHON"}
#     ]
#   end

#   test_with_params "vmSha3Test1", fn config_name ->
#     json_test = load_test_config(:vmSha3Test, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:sha3_0},
#       {:sha3_1},
#       {:sha3_2},
#       {:sha3_3},
#       {:sha3_4},
#       # {:sha3_5}, # binary_alloc: Cannot reallocate n bytes of memory
#       # {:sha3_6}, # binary_alloc: Cannot reallocate n bytes of memory
#       {:sha3_bigOffset},
#       {:sha3_bigOffset2},
#       # {:sha3_bigSize},
#       {:sha3_memSizeNoQuadraticCost31},
#       {:sha3_memSizeQuadraticCost32},
#       # {:sha3_memSizeQuadraticCost32_zeroSize}, #not working
#       {:sha3_memSizeQuadraticCost33},
#       {:sha3_memSizeQuadraticCost63},
#       {:sha3_memSizeQuadraticCost64},
#       {:sha3_memSizeQuadraticCost64_2},
#       {:sha3_memSizeQuadraticCost65}
#     ]
#   end

#   test_with_params "vmSystemOperations1", fn config_name ->
#     json_test = load_test_config(:vmSystemOperations, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       {:ABAcalls0},
#       # {:ABAcalls1}, # exception
#       # {:ABAcalls2}, # exception
#       # {:ABAcalls3}, # exception
#       # {:ABAcallsSuicide0}, # not working
#       {:ABAcallsSuicide1},
#       # {:CallRecursiveBomb0},
#       # {:CallRecursiveBomb1}, # not working
#       # {:CallRecursiveBomb2}, # not working
#       # {:CallRecursiveBomb3}, # not working
#       {:CallToNameRegistrator0},
#       {:CallToNameRegistratorNotMuchMemory0},
#       {:CallToNameRegistratorNotMuchMemory1},
#       {:CallToNameRegistratorOutOfGas},
#       {:CallToNameRegistratorTooMuchMemory0},
#       {:CallToNameRegistratorTooMuchMemory1},
#       {:CallToNameRegistratorTooMuchMemory2},
#       # {:CallToPrecompiledContract}, # not working
#       {:CallToReturn1},
#       {:PostToNameRegistrator0},
#       {:PostToReturn1},
#       {:TestNameRegistrator},
#       # {:callcodeToNameRegistrator0}, # not working
#       # {:callcodeToReturn1}, # not working
#       {:callstatelessToNameRegistrator0},
#       {:callstatelessToReturn1},
#       # {:createNameRegistrator}, # not working
#       # {:createNameRegistratorOutOfMemoryBonds0}, # TODO
#       # {:createNameRegistratorOutOfMemoryBonds1}, # TODO
#       # {:createNameRegistratorValueTooHigh}, # TODO
#       {:return0},
#       {:return1},
#       {:return2}
#       # {:suicide0}, # TODO
#       # {:suicideNotExistingAccount}, # TODO
#       # {:suicideSendEtherToMe} # TODO
#     ]
#   end

#   test_with_params "vmTests1", fn config_name ->
#     json_test = load_test_config(:vmTests, config_name)
#     extract_and_validate(json_test, config_name)
#   end do
#     [
#       # {:arith}, # exception
#       # {:boolean}, # exception
#       # {:mktx}, # exception
#       # {:suicide} # not working
#     ]
#   end

#   defp load_test_config(config_folder_atom, config_name_atom) do
#     config_folder_string = Atom.to_string(config_folder_atom)
#     config_name_string = Atom.to_string(config_name_atom)

#     config =
#       File.read!(
#         "../../aevm_external/ethereum_tests/VMTests/#{config_folder_string}/#{config_name_string}.json"
#       )

#     json_test = Poison.decode!(config, keys: :atoms)

#     parse_config_value(
#       json_test |> Map.to_list() |> Enum.sort(),
#       config_structure() |> Map.to_list() |> Enum.sort(),
#       %{}
#     )
#   end

#   defp parse_config_value([], [], result) do
#     result
#   end

#   defp parse_config_value(
#          [],
#          [{:multiple_bin_int, _}],
#          result
#        ) do
#     result
#   end

#   defp parse_config_value([{c_key, c_value}], [{:multiple_atom, s_value}], result) do
#     Map.put(
#       result,
#       c_key,
#       parse_config_value(
#         c_value |> Map.to_list() |> Enum.sort(),
#         s_value |> Map.to_list() |> Enum.sort(),
#         %{}
#       )
#     )
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{:multiple_bin_int, :data_array_int}] = structure,
#          result
#        ) do
#     <<"0x", hex_bin::binary>> = Atom.to_string(c_key)
#     {new_c_key, _} = Integer.parse(hex_bin, 16)

#     c_value_bin = State.bytecode_to_bin(c_value)
#     byte_size = byte_size(c_value_bin)
#     bit_size = byte_size * 8
#     <<c_value_int::size(bit_size)>> = c_value_bin
#     <<new_c_value::unsigned-integer-256>> = <<c_value_int::unsigned-integer-256>>

#     new_result =
#       Map.put(
#         result,
#         new_c_key,
#         new_c_value
#       )

#     parse_config_value(c_rest, structure, new_result)
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{:multiple_bin_int, s_value} | _] = structure,
#          result
#        ) do
#     <<"0x", hex_bin::binary>> = Atom.to_string(c_key)
#     {new_c_key, _} = Integer.parse(hex_bin, 16)

#     new_result =
#       Map.put(
#         result,
#         new_c_key,
#         parse_config_value(
#           c_value |> Map.to_list() |> Enum.sort(),
#           s_value |> Map.to_list() |> Enum.sort(),
#           %{}
#         )
#       )

#     parse_config_value(c_rest, structure, new_result)
#   end

#   defp parse_config_value(
#          [{c_key, _c_value} | _c_rest] = config,
#          [{s_key, _s_value} | s_rest] = _structure,
#          result
#        )
#        when c_key !== s_key do
#     parse_config_value(config, s_rest, result)
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{_, :string} | s_rest] = _structure,
#          result
#        ) do
#     parse_config_value(c_rest, s_rest, Map.put(result, c_key, c_value))
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{_, :bin_int} | s_rest] = _structure,
#          result
#        ) do

#     c_value =
#       if c_value == "" do
#         "0x0"
#       else
#         c_value
#       end

#     <<"0x", hex_bin::binary>> = c_value
#     {new_value, _} = Integer.parse(hex_bin, 16)

#     parse_config_value(
#       c_rest,
#       s_rest,
#       Map.put(result, c_key, new_value)
#     )
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{_, :data_hex} | s_rest] = _structure,
#          result
#        ) do
#     <<"0x", bytecode::binary>> = c_value
#     parse_config_value(c_rest, s_rest, Map.put(result, c_key, State.bytecode_to_bin(bytecode)))
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{_, :data_array} | s_rest] = _structure,
#          result
#        ) do
#     parse_config_value(
#       c_rest,
#       s_rest,
#       Map.put(result, c_key, State.bytecode_to_bin(c_value))
#     )
#   end

#   defp parse_config_value([{c_key, c_value} | c_rest], [{_, :unclear} | s_rest], result) do
#     parse_config_value(c_rest, s_rest, Map.put(result, c_key, c_value))
#   end

#   defp parse_config_value(
#          [{:callcreates, c_value} | c_rest] = _config,
#          [{_s_key, [s_value]} | s_rest] = _structure,
#          result
#        ) do
#     callcreates =
#       Enum.reduce(c_value, [], fn c, acc ->
#         [
#           parse_config_value(
#             c |> Map.to_list() |> Enum.sort(),
#             s_value |> Map.to_list() |> Enum.sort(),
#             %{}
#           )
#           | acc
#         ]
#       end)

#     new_result = Map.put(result, :callcreates, callcreates)

#     parse_config_value(
#       c_rest,
#       s_rest,
#       new_result
#     )
#   end

#   defp parse_config_value(
#          [{c_key, c_value} | c_rest] = _config,
#          [{_s_key, s_value} | s_rest] = _structure,
#          result
#        ) do
#     new_result =
#       Map.put(
#         result,
#         c_key,
#         parse_config_value(
#           c_value |> Map.to_list() |> Enum.sort(),
#           s_value |> Map.to_list() |> Enum.sort(),
#           %{}
#         )
#       )

#     parse_config_value(
#       c_rest,
#       s_rest,
#       new_result
#     )
#   end

#   defp config_structure do
#     %{
#       :multiple_atom => %{
#         :_info => %{
#           :comment => :string,
#           :filledwith => :string,
#           :source => :string,
#           :sourceHash => :string,
#           :lllcversion => :string
#         },
#         :callcreates => [
#           %{
#             :data => :data_array,
#             :destination => :bin_int,
#             :gasLimit => :bin_int,
#             :value => :bin_int
#           }
#         ],
#         :env => %{
#           :currentCoinbase => :bin_int,
#           :currentDifficulty => :bin_int,
#           :currentGasLimit => :bin_int,
#           :currentNumber => :bin_int,
#           :currentTimestamp => :bin_int
#         },
#         :exec => %{
#           :address => :bin_int,
#           :caller => :bin_int,
#           :code => :data_hex,
#           :data => :data_array,
#           :gas => :bin_int,
#           :gasPrice => :bin_int,
#           :origin => :bin_int,
#           :value => :bin_int
#         },
#         :gas => :bin_int,
#         :logs => :unclear,
#         :out => :data_array,
#         :post => %{
#           :multiple_bin_int => %{
#             :balance => :bin_int,
#             :code => :data_array,
#             :nonce => :bin_int,
#             :storage => %{:multiple_bin_int => :data_array_int}
#           }
#         },
#         :pre => %{
#           :multiple_bin_int => %{
#             :balance => :bin_int,
#             :code => :data_array,
#             :nonce => :bin_int,
#             :storage => %{:multiple_bin_int => :data_array_int}
#           }
#         }
#       }
#     }
#   end
# end
