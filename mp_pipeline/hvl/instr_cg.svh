covergroup instr_cg with function sample(instr_t instr);
    // ========================================
    // Basic Coverpoints
    // ========================================
    all_opcodes   : coverpoint instr.i_type.opcode;
    all_funct7    : coverpoint funct7_t'(instr.r_type.funct7);
    all_funct3    : coverpoint instr.i_type.funct3;
    all_regs_rs1  : coverpoint instr.r_type.rs1;
    all_regs_rs2  : coverpoint instr.r_type.rs2;

    // ========================================
    // funct7 coverpoint
    // ========================================
    coverpoint instr.r_type.funct7 {
        bins range[] = {[0:$]};
        ignore_bins not_in_spec = {[1:31], [33:127]};
    }

    // ========================================
    // Cross: opcode × funct3
    // 明确排除所有 17 个 illegal 组合
    // ========================================
    funct3_cross : cross instr.i_type.opcode, instr.i_type.funct3 {
        // JAL - 不使用 funct3，排除所有 8 个组合
        ignore_bins JAL_ALL = funct3_cross with (instr.i_type.opcode == op_jal);
        
        // AUIPC - 不使用 funct3，排除所有 8 个组合
        ignore_bins AUIPC_ALL = funct3_cross with (instr.i_type.opcode == op_auipc);
        
        // LUI - 不使用 funct3，排除所有 8 个组合
        ignore_bins LUI_ALL = funct3_cross with (instr.i_type.opcode == op_lui);

        // JALR - 只允许 funct3=0，排除 funct3=1,2,3,4,5,6,7
        ignore_bins JALR_F3_1 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd1);
        ignore_bins JALR_F3_2 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd2);
        ignore_bins JALR_F3_3 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd3);
        ignore_bins JALR_F3_4 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd4);
        ignore_bins JALR_F3_5 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd5);
        ignore_bins JALR_F3_6 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd6);
        ignore_bins JALR_F3_7 = funct3_cross with (instr.i_type.opcode == op_jalr && instr.i_type.funct3 == 3'd7);

        // BRANCH - 只允许 0,1,4,5,6,7，排除 funct3=2,3
        ignore_bins BR_F3_2 = funct3_cross with (instr.i_type.opcode == op_br && instr.i_type.funct3 == 3'd2);
        ignore_bins BR_F3_3 = funct3_cross with (instr.i_type.opcode == op_br && instr.i_type.funct3 == 3'd3);

        // LOAD - 只允许 0,1,2,4,5，排除 funct3=3,6,7
        ignore_bins LOAD_F3_3 = funct3_cross with (instr.i_type.opcode == op_load && instr.i_type.funct3 == 3'd3);
        ignore_bins LOAD_F3_6 = funct3_cross with (instr.i_type.opcode == op_load && instr.i_type.funct3 == 3'd6);
        ignore_bins LOAD_F3_7 = funct3_cross with (instr.i_type.opcode == op_load && instr.i_type.funct3 == 3'd7);

        // STORE - 只允许 0,1,2，排除 funct3=3,4,5,6,7
        ignore_bins STORE_F3_3 = funct3_cross with (instr.i_type.opcode == op_store && instr.i_type.funct3 == 3'd3);
        ignore_bins STORE_F3_4 = funct3_cross with (instr.i_type.opcode == op_store && instr.i_type.funct3 == 3'd4);
        ignore_bins STORE_F3_5 = funct3_cross with (instr.i_type.opcode == op_store && instr.i_type.funct3 == 3'd5);
        ignore_bins STORE_F3_6 = funct3_cross with (instr.i_type.opcode == op_store && instr.i_type.funct3 == 3'd6);
        ignore_bins STORE_F3_7 = funct3_cross with (instr.i_type.opcode == op_store && instr.i_type.funct3 == 3'd7);
    }

    // ========================================
    // Cross: opcode × funct3 × funct7
    // ========================================
    funct7_cross : cross instr.r_type.opcode, instr.r_type.funct3, instr.r_type.funct7 {
        // 只有 op_reg 和 op_imm 使用 funct7
        ignore_bins OTHER_INSTS = funct7_cross with
            (!(instr.r_type.opcode inside {op_reg, op_imm}));

        // op_reg 和 op_imm 的其他限制
        ignore_bins reg_funct7 = funct7_cross with 
            ((instr.r_type.funct3 inside {add, slt, axor, aor, aand, sltu}) && 
             (instr.r_type.opcode == op_imm));
        
        ignore_bins reg_funct7_2 = funct7_cross with 
            ((instr.r_type.funct3 == sll) && 
             (instr.r_type.opcode == op_imm) && 
             (instr.r_type.funct7 == variant));
        
        ignore_bins ignorevariant = funct7_cross with
            (!(instr.r_type.funct3 inside {add, sr}) && 
             !(instr.r_type.funct7 == base));
    }

endgroup : instr_cg