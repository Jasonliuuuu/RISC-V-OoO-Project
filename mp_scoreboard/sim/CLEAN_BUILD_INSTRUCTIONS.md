# Clean Build Instructions - IMPORTANT

## Problem Discovered

When you ran `make run_random`, QuestaSim displayed this message:
```
# ** Note: (vsim-8009) Loading existing optimized design _opt
```

This means QuestaSim was using **cached compiled code from BEFORE the RVFI fixes were applied**!

## Why This Happened

1. ✅ All RVFI fixes ARE in your source code (commit 9ed654f)
2. ✅ `make clean` removed the `work` directory
3. ❌ BUT QuestaSim cached an "optimized design" in hidden files
4. ❌ So it simulated OLD buggy code instead of your fixed code

## Solution: Force Complete Clean Build

Run these commands on your server to force a fresh build:

```bash
# Go to sim directory
cd /home/user/RISC-V-OoO-Project/mp_scoreboard/sim

# IMPORTANT: Remove QuestaSim's optimization cache
# (This is what make clean missed)
rm -rf work/_opt* work/_dbcontainer

# Optional: Complete clean to be absolutely sure
make clean

# Now rebuild with fixed code
make run_random
```

## Expected Result

After the clean rebuild, you should see:
- ✅ Compilation completes successfully
- ✅ NO message about "Loading existing optimized design"
- ✅ LUI instructions report `rs1_addr=0, rs2_addr=0, rd_wdata=<immediate>`
- ✅ No more RVFI Monitor errors
- ✅ Simulation completes successfully

## What Changed in the Fixed Code

The RVFI fixes (commit 602d6f7) include:

### 1. Scoreboard Register Address Fix (scoreboard.sv:182-201)
```systemverilog
// New logic to zero source registers for instructions that don't read them
case (opcode)
    op_lui, op_auipc, op_jal: begin
        actual_rs1 = 5'b0;
        actual_rs2 = 5'b0;
    end
    default: begin
        actual_rs1 = rs1;
        actual_rs2 = rs2;
    end
endcase
```

### 2. ALU Operand Selection Fix (fu_alu.sv:75-96)
```systemverilog
// Use PC for AUIPC/JAL/JALR instead of always using Rs1
assign operand_a = (current_inst.opcode == op_auipc ||
                    current_inst.opcode == op_jal ||
                    current_inst.opcode == op_jalr) ?
                   current_inst.pc : current_inst.vj;
```

### 3. Jump Target Calculation Fix (fu_alu.sv:215-225)
```systemverilog
// Correct pc_wdata for jump instructions
if (current_inst.opcode == op_jal) begin
    fu_if.complete_data.pc_wdata = current_inst.pc + current_inst.imm;
end else if (current_inst.opcode == op_jalr) begin
    fu_if.complete_data.pc_wdata = (current_inst.vj + current_inst.imm) & ~32'b1;
end else begin
    fu_if.complete_data.pc_wdata = current_inst.pc + 4;
end
```

## Verification

To verify the fixes are in your source code, run:
```bash
cd /home/user/RISC-V-OoO-Project/mp_scoreboard/sim
./verify_fixes.sh
```

All 4 checks should pass (✓).

## If Problems Persist

If you still see RVFI errors after a clean rebuild:

1. **Check you're on the right commit:**
   ```bash
   git log --oneline -1
   # Should show: 9ed654f fix: Improve grep patterns in verification script
   ```

2. **Verify fixes are in source code:**
   ```bash
   grep -n "actual_rs1" ../hdl/scoreboard/scoreboard.sv | head -1
   # Should show line 182 with actual_rs1/actual_rs2 declaration
   ```

3. **Check simulation output for the cache message:**
   ```bash
   grep "Loading existing optimized design" run/random_tb_sim.log
   # Should return NOTHING after clean rebuild
   ```

## Prevention: Add .gitignore

These build artifacts should never be committed to git. Create a `.gitignore`:

```bash
cd /home/user/RISC-V-OoO-Project/mp_scoreboard/sim
cat > .gitignore << 'EOF'
# QuestaSim/ModelSim build artifacts
work/
run/
transcript
vsim.wlf
*.log
modelsim.ini
vsim.ucdb
coverage_report/
_opt*/
*.vstf
.*.vstf
vsim.dbg

# Simulation outputs
commit.log
EOF
```

---

**Last Updated:** 2025-11-06
**Commit with Fixes:** 602d6f7, 4255188, 403a748, 9ed654f
