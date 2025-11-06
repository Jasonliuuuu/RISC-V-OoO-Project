#!/bin/bash
echo "=== Verifying RVFI Fixes ==="
echo ""
echo "1. Checking scoreboard.sv for actual_rs1/actual_rs2 logic..."
if grep -q "actual_rs1" ../hdl/scoreboard/scoreboard.sv; then
    echo "   ✓ actual_rs1/actual_rs2 signals present"
else
    echo "   ✗ MISSING: actual_rs1/actual_rs2 signals"
fi

echo ""
echo "2. Checking scoreboard.sv for conditional register zeroing..."
if grep -q "op_lui, op_auipc, op_jal:" ../hdl/scoreboard/scoreboard.sv; then
    echo "   ✓ LUI/AUIPC/JAL register zeroing logic present"
else
    echo "   ✗ MISSING: LUI/AUIPC/JAL register zeroing"
fi

echo ""
echo "3. Checking fu_alu.sv for corrected operand_a selection..."
if grep -q "op_auipc.*op_jal.*op_jalr" ../hdl/functional_units/fu_alu.sv; then
    echo "   ✓ Corrected operand_a selection for special instructions"
else
    echo "   ✗ MISSING: operand_a fix for AUIPC/JAL/JALR"
fi

echo ""
echo "4. Checking fu_alu.sv for jump target calculation..."
if grep -q "pc_wdata.*op_jal" ../hdl/functional_units/fu_alu.sv; then
    echo "   ✓ Jump target calculation logic present"
else
    echo "   ✗ MISSING: Jump target calculation"
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "If all checks pass (✓), the fixes are in place."
echo "Now run: make run_random"
