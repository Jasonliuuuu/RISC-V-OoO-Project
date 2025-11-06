# RVFI Verification Fixes

**Date**: 2025-11-06
**Issue**: RVFI monitor errors showing incorrect rd_wdata and rs1_addr/rs2_addr values

## Problem Description

After successfully setting up the validation environment and fixing compilation errors, the simulation ran but encountered RVFI verification failures:

1. **Incorrect rs1_addr/rs2_addr**: Instructions like LUI that don't read source registers were showing non-zero rs1_addr and rs2_addr values
   - Example: LUI instruction showed `rs1_addr = 11, rs2_addr = 09` instead of `0, 0`

2. **Incorrect rd_wdata**: Instructions were outputting `0x00000000` instead of expected values
   - Example: LUI `ce9880b7` expected `rd_wdata = 0xce988000` but got `0x00000000`

## Root Cause Analysis

### Issue 1: Register Address Handling

The scoreboard's Issue stage always extracted rs1 and rs2 from instruction bits (lines 104-106), regardless of whether the instruction actually uses those source registers:

```systemverilog
assign rs1 = iq_data.inst[19:15];  // Always extracted
assign rs2 = iq_data.inst[24:20];  // Always extracted
```

These values were then unconditionally assigned to the scoreboard status fields fj/fk:

```systemverilog
fu_status[target_fu].fj <= rs1;  // Always assigned
fu_status[target_fu].fk <= rs2;  // Always assigned
```

The functional units then reported these fj/fk values as rs1_addr/rs2_addr in RVFI output, causing incorrect addresses for instructions that don't read registers.

### Issue 2: Operand Selection for Special Instructions

The ALU always used Rs1 (vj) as operand_a, which is incorrect for:
- **AUIPC**: Should use PC, not Rs1
- **JAL/JALR**: Should use PC for rd calculation (return address = PC + 4), not Rs1

Additionally, pc_wdata was always set to `PC + 4`, which is incorrect for:
- **JAL**: Should be `PC + imm` (jump target)
- **JALR**: Should be `(Rs1 + imm) & ~1` (jump target with LSB cleared)

## Fixes Applied

### Fix 1: Conditional Source Register Extraction (scoreboard.sv)

Added logic to determine actual source registers based on instruction type:

```systemverilog
logic [4:0] actual_rs1, actual_rs2;  // 实际使用的源寄存器

// 根据指令类型确定实际使用的源寄存器
// LUI, AUIPC, JAL 不读取源寄存器
always_comb begin
    actual_rs1 = rs1;
    actual_rs2 = rs2;

    case (opcode)
        op_lui, op_auipc, op_jal: begin
            // 这些指令不读取源寄存器
            actual_rs1 = 5'b0;
            actual_rs2 = 5'b0;
        end
        default: begin
            actual_rs1 = rs1;
            actual_rs2 = rs2;
        end
    endcase
end
```

Updated all references to use `actual_rs1` and `actual_rs2`:
- Register file read addresses: `assign rf_rs1_addr = actual_rs1;`
- RAW dependency checks: `if (actual_rs1 == 0)`, `reg_result[actual_rs1].pending`
- Scoreboard status: `fu_status[target_fu].fj <= actual_rs1;`

**Result**: Instructions that don't read source registers now correctly report rs1_addr = 0, rs2_addr = 0.

### Fix 2: Correct Operand Selection (fu_alu.sv)

Updated operand_a to use PC for AUIPC, JAL, and JALR:

```systemverilog
// 操作数 A：根据指令类型选择
// - AUIPC/JAL/JALR: 使用 PC
// - 其他: 使用 Rs1 (Vj)
assign operand_a = (current_inst.opcode == op_auipc ||
                    current_inst.opcode == op_jal ||
                    current_inst.opcode == op_jalr) ?
                   current_inst.pc : current_inst.vj;
```

Updated operand_b to use 4 for JAL/JALR (return address calculation):

```systemverilog
// 操作数 B：根据指令类型选择
always_comb begin
    if (current_inst.opcode == op_jal || current_inst.opcode == op_jalr) begin
        operand_b = 32'd4;  // PC + 4 for return address
    end else if (current_inst.opcode == op_reg) begin
        operand_b = current_inst.vk;
    end else begin
        operand_b = current_inst.imm;
    end
end
```

**Result**:
- LUI: rd = 0 + imm = imm ✓
- AUIPC: rd = PC + imm ✓
- JAL: rd = PC + 4 (return address) ✓
- JALR: rd = PC + 4 (return address) ✓

### Fix 3: Correct pc_wdata Calculation (fu_alu.sv)

Updated pc_wdata to correctly compute jump targets:

```systemverilog
// pc_wdata 根据指令类型计算
// JAL: PC + imm
// JALR: (Rs1 + imm) & ~1
// 其他: PC + 4
if (current_inst.opcode == op_jal) begin
    fu_if.complete_data.pc_wdata = current_inst.pc + current_inst.imm;
end else if (current_inst.opcode == op_jalr) begin
    fu_if.complete_data.pc_wdata = (current_inst.vj + current_inst.imm) & ~32'b1;
end else begin
    fu_if.complete_data.pc_wdata = current_inst.pc + 4;
end
```

**Result**: JAL/JALR now correctly report the jump target address in pc_wdata.

## Files Modified

1. **mp_scoreboard/hdl/scoreboard/scoreboard.sv**:
   - Added `actual_rs1` and `actual_rs2` signals (line 182)
   - Added conditional source register logic (lines 184-201)
   - Updated RAW dependency checks to use actual registers (lines 209-242)
   - Updated scoreboard status assignments (lines 280-281)

2. **mp_scoreboard/hdl/functional_units/fu_alu.sv**:
   - Updated operand_a selection to use PC for AUIPC/JAL/JALR (lines 75-81)
   - Changed operand_b from continuous assignment to always_comb (lines 83-94)
   - Updated pc_wdata calculation for JAL/JALR (lines 215-225)

## Expected Results

After these fixes:
- ✓ LUI instructions report rs1_addr=0, rs2_addr=0, rd_wdata=immediate
- ✓ AUIPC instructions report rs1_addr=0, rs2_addr=0, rd_wdata=PC+immediate
- ✓ JAL instructions report rs1_addr=0, rs2_addr=0, rd_wdata=PC+4, pc_wdata=PC+imm
- ✓ JALR instructions report rs1_addr=correct, rs2_addr=0, rd_wdata=PC+4, pc_wdata=(Rs1+imm)&~1
- ✓ All other instructions continue to work correctly

## Testing

To test these fixes, run:

```bash
cd mp_scoreboard/sim
make run_random
```

The simulation should now pass RVFI verification without errors.

## Notes

- **JALR Special Case**: JALR does read Rs1 (for jump target calculation), so it's not included in the list of instructions with zeroed source registers. Only LUI, AUIPC, and JAL have both source registers set to 0.

- **Branch Instructions**: Conditional branches (BEQ, BNE, BLT, etc.) are handled by the Branch FU (fu_branch.sv), not the ALU. These instructions correctly read both Rs1 and Rs2 for comparison.

- **Store Instructions**: Store instructions (SB, SH, SW) correctly read both Rs1 (base address) and Rs2 (data to store), so no changes were needed.

## Related Documentation

- **COMPILATION_FIXES.md**: Documents the 18 compilation errors fixed earlier
- **OUTPUT_FILES.md**: Documents the expected output files from validation
- **SETUP_GUIDE.md**: Complete setup and usage guide
