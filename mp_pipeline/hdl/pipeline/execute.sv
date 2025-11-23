module execute
    import forward_amux::*;
    import forward_bmux::*;
    import rv32i_types::*;
(
    input  id_ex_stage_reg_t id_ex,
    output ex_mem_stage_reg_t ex_mem,

    input  logic [31:0] regfilemux_out_forward,
    input  logic        ex_mem_br_en_forward,
    input  logic [31:0] ex_mem_alu_out_forward,
    input  logic [31:0] ex_mem_u_imm_forward,

    input  forward_a_sel_t forward_a_sel,
    input  forward_b_sel_t forward_b_sel,

    input  logic flush_pipeline
);


    assign ex_mem.pc    = id_ex.pc;
    // Flush in-flight instruction when branch/jump detected
    assign ex_mem.valid = flush_pipeline ? 1'b0 : id_ex.valid;
    // Propagate speculative flag (will be overridden in cpu.sv pipeline register)
    assign ex_mem.is_speculative = id_ex.is_speculative;

    // forward A
    logic [31:0] a_src;
    always_comb begin
        unique case (forward_a_sel)
            forward_amux::rs1_v:        a_src = id_ex.rs1_v;
            forward_amux::br_en:        a_src = {31'b0, ex_mem_br_en_forward};
            forward_amux::alu_out:      a_src = ex_mem_alu_out_forward;
            forward_amux::regfilemux_out: a_src = regfilemux_out_forward;
            forward_amux::u_imm:        a_src = ex_mem_u_imm_forward;
            default:                    a_src = id_ex.rs1_v;
        endcase
    end

    // forward B
    logic [31:0] b_src;
    always_comb begin
        unique case (forward_b_sel)
            forward_bmux::rs2_v:        b_src = id_ex.rs2_v;
            forward_bmux::br_en:        b_src = {31'b0, ex_mem_br_en_forward};
            forward_bmux::alu_out:      b_src = ex_mem_alu_out_forward;
            forward_bmux::regfilemux_out: b_src = regfilemux_out_forward;
            forward_bmux::u_imm:        b_src = ex_mem_u_imm_forward;
            default:                    b_src = id_ex.rs2_v;
        endcase
    end

    // ALU operands
    logic [31:0] alu_a;
    logic [31:0] alu_b;

    always_comb begin
        alu_a = id_ex.alu_m1_sel ? id_ex.pc : a_src;
        alu_b = id_ex.alu_m2_sel ? id_ex.imm_out : b_src;
    end

    logic [31:0] alu_result;
    alu alu_i(
        .a(alu_a),
        .b(alu_b),
        .aluop(id_ex.alu_op),
        .f(alu_result)
    );

    assign ex_mem.alu_out = alu_result;

    // CMP
    logic [31:0] cmp_b;
    assign cmp_b = (id_ex.cmp_sel ? id_ex.i_imm : b_src);

    cmp cmp_i(
        .a(a_src),
        .b(cmp_b),
        .cmpop(id_ex.cmpop),
        .br_en(ex_mem.br_en)
    );

    // Propagate to EX/MEM register
    assign ex_mem.inst        = id_ex.inst;
    assign ex_mem.rs1_v       = a_src;
    assign ex_mem.rs2_v       = b_src;
    assign ex_mem.u_imm       = id_ex.u_imm;
    assign ex_mem.opcode      = id_ex.opcode;
    assign ex_mem.funct3      = id_ex.funct3;
    assign ex_mem.funct7      = id_ex.funct7;
    assign ex_mem.rd_s        = id_ex.rd_s;
    assign ex_mem.rs1_s       = id_ex.rs1_s;
    assign ex_mem.rs2_s       = id_ex.rs2_s;
    assign ex_mem.j_imm       = id_ex.j_imm;
    assign ex_mem.b_imm       = id_ex.b_imm;
    assign ex_mem.i_imm       = id_ex.i_imm;
    assign ex_mem.s_imm       = id_ex.s_imm;

    // NEW: Pre-calculate branch target in EX stage for stable value
    // This eliminates combinational glitches in MEM stage
    logic [31:0] branch_target_calc;
    always_comb begin
        if (id_ex.opcode == op_jal)
            branch_target_calc = alu_result;  // JAL: PC + imm
        else if (id_ex.opcode == op_jalr)
            branch_target_calc = alu_result & 32'hFFFF_FFFE;  // JALR: (rs1 + imm) & ~1
        else if (id_ex.opcode == op_br)
            branch_target_calc = alu_result;  // BRANCH: PC + imm
        else
            branch_target_calc = alu_result;  // Default
    end
    assign ex_mem.branch_target = branch_target_calc;

    // Physical register assignment (rename)
    always_comb begin
        ex_mem.rs1_arch      = id_ex.rs1_arch;
        ex_mem.rs2_arch      = id_ex.rs2_arch;
        ex_mem.rs1_phys      = id_ex.rs1_phys;
        ex_mem.rs2_phys      = id_ex.rs2_phys;
        ex_mem.dest_phys_new = id_ex.dest_phys_new;
        ex_mem.dest_phys_old = id_ex.dest_phys_old;
        ex_mem.dest_arch     = id_ex.dest_arch;

        ex_mem.regf_we       = id_ex.regf_we;
        ex_mem.regfilemux_sel = id_ex.regfilemux_sel;
    end

endmodule
