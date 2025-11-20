# Pipeline Debugging Summary (English)

## Overview

This document details all critical bugs discovered and fixed during the RISC-V Out-of-Order Pipeline debugging process. The pipeline successfully progressed from failing at instruction #0 to executing 38+ instructions with proper control flow integrity.

**Final Status:**
- ✅ Complete pipeline flush logic implemented
- ✅ AUIPC instruction bug fixed
- ✅ Instructions committed: 38+
- ✅ IPC: ~0.69
- ⚠️ Further debugging needed for 60k instruction target

---

## Critical Bug #1: Incomplete Pipeline Flush Logic

### Problem Description

**Symptom:**
- RVFI verification error: "mismatch with shadow pc"
- Instructions committing after branch/jump that should have been flushed
- Example: After JALR @ PC=0x84 jumps to 0xdb139d42, LUI @ PC=0x88 still committed

**Root Cause:**
The original pipeline flush mechanism (`flushing_inst`) only affected the decode stage. When a branch/jump was detected in the MEM stage:
- Instructions already in IF/ID, ID/EX, and EX/MEM stages continued executing
- These "in-flight" instructions incorrectly committed, violating control flow integrity

### Solution

Implemented **complete 4-stage pipeline flush**:

#### 1. Signal Renaming
```systemverilog
// Old: flushing_inst (inconsistent usage)
// New: flush_pipeline (clear purpose)
```

#### 2. Fetch Stage (fetch.sv)
```systemverilog
// Flush IF/ID valid bit
if(flush_pipeline) begin
    if_id_reg_before.valid <= 1'b0;
    if_id_reg_before.pc    <= pc;
end

// Flush instruction and response
if (flush_pipeline) begin
    imem_rdata_id <= 32'h0000_0013;  // NOP
    imem_resp_id  <= 1'b0;
end
```

#### 3. Decode Stage (decode.sv)
```systemverilog
assign id_ex.valid = flush_pipeline ? 1'b0 : if_id.valid;
```

#### 4. Execute Stage (execute.sv)
```systemverilog
assign ex_mem.valid = flush_pipeline ? 1'b0 : id_ex.valid;
```

#### 5. Memory Stage (memstage.sv) ⭐ **CRITICAL**
```systemverilog
// This was the KEY missing piece!
assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
```

**Why MEM/WB flush is critical:**
- Writeback commits instructions when `mem_wb.valid && !freeze_stall`
- Without MEM/WB flush, flushed instructions still had `valid=1` when reaching WB
- Result: They committed despite being flushed!

#### 6. CPU Integration (cpu.sv)
```systemverilog
// Updated all signal declarations and connections
logic flush_pipeline;  // was: flushing_inst

// All pipeline stages now use flush_pipeline
```

### Verification Results

**Before Fix:**
- 37 instructions committed
- LUI @ 0x88 + STORE @ 0x90 both committed after JALR (WRONG)

**After Fix:**
- 34 instructions committed
- Both LUI and STORE properly flushed (CORRECT)
- Control flow integrity restored ✅

---

## Critical Bug #2: AUIPC Instruction Calculation Error

### Problem Description

**Symptom:**
- RVFI verification error: "mismatch in rd_wdata" at instruction #32
- Instruction: `AUIPC x2, 0xe4594000` at PC=0x60000080
- Expected: `0x44594080` (PC + imm, truncated to 32-bit)
- Actual: `0xa2499080`

**Root Cause Investigation:**

Manual code trace revealed the issue in `decode.sv`:

```systemverilog
// Line 224-225 BEFORE FIX:
assign id_ex.alu_m2_sel =
    (curr_opcode inside {op_store, op_load, op_imm, op_jalr}) ? 1'b1 : 1'b0;
    // ❌ Missing op_auipc!
```

**Impact:**
1. For AUIPC: `alu_m2_sel = 0`
2. In execute stage: `alu_b = alu_m2_sel ? imm_out : b_src`
3. Result: `alu_b = b_src` (forwarded rs2 value) ❌
4. AUIPC computed: `rd = PC + b_src` instead of `rd = PC + imm`

### Solution

```systemverilog
// decode.sv line 224-225 AFTER FIX:
assign id_ex.alu_m2_sel =
    (curr_opcode inside {op_auipc, op_store, op_load, op_imm, op_jalr}) ? 1'b1 : 1'b0;
    // ✅ Added op_auipc
```

**AUIPC Data Flow (Corrected):**
1. **Decode**: 
   - `alu_m1_sel = 1` → use PC as ALU operand A
   - `alu_m2_sel = 1` → use imm_out as ALU operand B ✅
   - `regfilemux_sel = alu_out`

2. **Execute**:
   - `alu_a = id_ex.pc` (0x60000080)
   - `alu_b = id_ex.imm_out` (0xe4594000) ✅
   - `alu_out = alu_a + alu_b` = 0x144594080 → 0x44594080

3. **Writeback**:
   - `rd_v = alu_out` = 0x44594080 ✅

### Verification Results

**Before Fix:**
- 34 instructions (stopped at AUIPC error)

**After Fix:**
- 38 instructions (+4) ✅
- AUIPC correctly computes `rd = PC + imm`

---

## Additional Fixes

### ALU Port Name Correction (execute.sv)
```systemverilog
// BEFORE:
alu alu_i(
    .f(id_ex.alu_op),      // ❌ Wrong: f is output, not input
    .result(alu_result)    // ❌ Wrong: no 'result' port
);

// AFTER:
alu alu_i(
    .aluop(id_ex.alu_op),  // ✅ Correct input port name
    .f(alu_result)         // ✅ Correct output port name
);
```

---

## Files Modified

1. **fetch.sv**
   - Added `flush_pipeline` input
   - Implemented IF/ID flush for valid and inst/resp signals

2. **decode.sv**
   - Renamed input: `flushing_inst` → `flush_pipeline`
   - Implemented ID/EX flush
   - **Fixed AUIPC bug**: Added `op_auipc` to `alu_m2_sel`

3. **execute.sv**
   - Renamed input: `flushing_inst` → `flush_pipeline`
   - Implemented EX/MEM flush
   - Fixed ALU port connections

4. **memstage.sv**
   - Renamed output: `flushing_inst` → `flush_pipeline`
   - **Implemented MEM/WB flush** (critical fix)

5. **cpu.sv**
   - Updated all signal declarations and connections
   - Propagated `flush_pipeline` to all stages

---

## Testing & Validation

### Test Environment
- Testbench: `random_tb.sv` with constrained random verification
- Verification: RVFI (RISC-V Formal Interface) with golden model
- Target: 60,000 instruction execution

### Results
- **Initial**: Failed at instruction #0
- **After Flush Fix**: 34 instructions
- **After AUIPC Fix**: 38 instructions
- **IPC**: ~0.69 (acceptable for in-order pipeline with flushes)

---

## Lessons Learned

1. **Complete Flush is Essential**: Missing even one pipeline stage (MEM/WB) in flush logic breaks the entire mechanism

2. **Signal Naming Matters**: Inconsistent naming (`flushing_inst` vs `flush_pipeline`) led to bugs

3. **Opcode Coverage**: When setting mux control signals, ensure ALL relevant opcodes are included

4. **Manual Code Trace**: When debug statements don't work, systematic manual code tracing can reveal the root cause

5. **Port Name Verification**: Always verify module port names match the actual module definition

---

## Remaining Work

Current errors at instruction 35-38:
- "mismatch with shadow pc"
- "mismatch in rd_wdata"
- "mismatch with shadow rs1"

These require further investigation to reach the 60,000 instruction target.

---

**Date**: November 19, 2025  
**Status**: Major bugs fixed, pipeline functional, continued debugging needed
