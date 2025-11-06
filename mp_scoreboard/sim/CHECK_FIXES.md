# RVFI Fixes Verification

## Status: All Fixes Present ✓

### 1. Scoreboard Register Address Fix (scoreboard.sv:182-201)
**Status**: ✓ PRESENT

Logic to set `actual_rs1 = 0, actual_rs2 = 0` for LUI/AUIPC/JAL instructions:
- Line 182: Declares `actual_rs1` and `actual_rs2` signals
- Lines 186-201: Case statement that zeros registers for instructions that don't read them
- Lines 280-281: Uses `actual_rs1` and `actual_rs2` when issuing to FUs

### 2. ALU Operand Selection Fix (fu_alu.sv:75-96)
**Status**: ✓ PRESENT

Corrected operand selection for special instructions:
- Lines 78-81: `operand_a` uses PC for AUIPC/JAL/JALR (instead of always using Rs1)
- Lines 88-96: `operand_b` uses 4 for JAL/JALR, immediate for others

### 3. Jump Target Calculation Fix (fu_alu.sv:215-225)
**Status**: ✓ PRESENT

Correct pc_wdata for jump instructions:
- Line 220: JAL sets `pc_wdata = PC + imm`
- Line 222: JALR sets `pc_wdata = (Rs1 + imm) & ~1`
- Line 224: Others set `pc_wdata = PC + 4`

## Expected Results After Rebuild

With these fixes, the simulation should now correctly handle:

1. **LUI** instructions:
   - ✓ rs1_addr = 0, rs2_addr = 0 (was showing non-zero before)
   - ✓ rd_wdata = immediate value (was showing 0x00000000 before)

2. **AUIPC** instructions:
   - ✓ rs1_addr = 0, rs2_addr = 0
   - ✓ rd_wdata = PC + immediate

3. **JAL** instructions:
   - ✓ rs1_addr = 0, rs2_addr = 0
   - ✓ rd_wdata = PC + 4 (return address)
   - ✓ pc_wdata = PC + immediate (jump target)

4. **JALR** instructions:
   - ✓ rs1_addr = correct source register
   - ✓ rs2_addr = 0
   - ✓ rd_wdata = PC + 4 (return address)
   - ✓ pc_wdata = (Rs1 + immediate) & ~1 (jump target)

## Next Steps

**You MUST rebuild** to apply these fixes:

```bash
cd /home/user/RISC-V-OoO-Project/mp_scoreboard/sim

# Clean old compiled files
make clean

# Rebuild and run with fixes
make run_random
```

The simulation should now pass RVFI verification without the errors you saw before.

## If Errors Still Occur

If you still see RVFI errors after rebuilding:
1. Check that you're on commit 4255188 or later: `git log --oneline -1`
2. Verify the source files have the fixes (check line numbers above)
3. Make sure you ran `make clean` before `make run_random`
4. Check the simulation log for different error messages

