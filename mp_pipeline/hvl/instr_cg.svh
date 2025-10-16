covergroup instr_cg with function sample(instr_t instr);
  // Easy covergroup to see that we're at least exercising
  // every opcode. Since opcode is an enum, this makes bins
  // for all its members.
  all_opcodes : coverpoint instr.i_type.opcode;
  

  // Some simple coverpoints on various instruction fields.
  // Recognize that these coverpoints are inherently less useful
  // because they really make sense in the context of the opcode itself.
  all_funct7 : coverpoint funct7_t'(instr.r_type.funct7);

  // TODO: Write the following coverpoints:

  // Check that funct3 takes on all possible values.
  all_funct3 : coverpoint (instr.i_type.funct3);

  // Check that the rs1 and rs2 fields across instructions take on
  // all possible values (each register is touched).
  all_regs_rs1 : coverpoint (instr.r_type.rs1);
  // all_regs_rs2 : coverpoint ... ;
  all_regs_rs2 : coverpoint (instr.r_type.rs2);



  // Now, cross coverage takes in the opcode context to correctly
  // figure out the /real/ coverage.
  funct3_cross : cross instr.i_type.opcode, instr.i_type.funct3 {
    // 这些 opcode 不使用 funct3
    ignore_bins JAL_FUNCT3 = funct3_cross with 
        (instr.i_type.opcode == op_jal);
    ignore_bins AUIPC_FUNCT3 = funct3_cross with
        (instr.i_type.opcode == op_auipc);
    ignore_bins LUI_FUNCT3 = funct3_cross with 
        (instr.i_type.opcode == op_lui);
  
    // 以下全部改成 ignore_bins
    ignore_bins BR_INVALID = funct3_cross with
        (instr.i_type.opcode == op_br 
         && !(instr.i_type.funct3 inside {beq, bne, blt, bge, bltu, bgeu}));
    
    ignore_bins LOAD_INVALID = funct3_cross with
        (instr.i_type.opcode == op_load
         && !(instr.i_type.funct3 inside {lb, lh, lw, lbu, lhu}));

    ignore_bins STORE_INVALID = funct3_cross with
        (instr.i_type.opcode == op_store
         && !(instr.i_type.funct3 inside {sb, sh, sw}));

    ignore_bins JALR_INVALID = funct3_cross with
        (instr.i_type.opcode == op_jalr && instr.i_type.funct3 != 0);
}
  // Coverpoint to make separate bins for funct7.
  coverpoint instr.r_type.funct7 {
    bins range[] = {[0:$]};
    ignore_bins not_in_spec = {[1:31], [33:127]};
  }
  // ignoring values, not indices, since funct7 only has value of 0 and 32

  // Cross coverage for funct7.
    funct7_cross : cross instr.r_type.opcode, instr.r_type.funct3, instr.r_type.funct7 {

    // No opcodes except op_reg and op_imm use funct7, so ignore the rest.
    ignore_bins OTHER_INSTS = funct7_cross with
    (!(instr.r_type.opcode inside {op_reg, op_imm}));

    ignore_bins reg_funct7 = funct7_cross with
    ((instr.r_type.funct3 inside {add, slt, axor, aor, aand, sltu, slt }) && (instr.r_type.opcode == op_imm ));

    ignore_bins reg_funct7_2 = funct7_cross with 
    ((instr.r_type.funct3 == sll) && (instr.r_type.opcode == op_imm) && (instr.r_type.funct7 == variant));

    ignore_bins ignorevariant = funct7_cross with
    (!(instr.r_type.funct3 inside {add, sr}) && !(instr.r_type.funct7 == base));
  

    // TODO: Get rid of all the other cases where funct7 isn't necessary, or cannot
    // take on certain values.
  }

endgroup : instr_cg



