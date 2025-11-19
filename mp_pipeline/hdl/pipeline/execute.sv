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

    input  logic flushing_inst
);


    assign ex_mem.pc    = id_ex.pc;
    assign ex_mem.valid = id_ex.valid;

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

    alu alu_i(
        .a(alu_a),
        .b(alu_b),
        .f(ex_mem.alu_out),
        .aluop(id_ex.alu_op)
    );

    // CMP
    logic [31:0] cmp_b;
    assign cmp_b = (id_ex.cmp_sel ? id_ex.i_imm : b_src);

    cmp cmp_i(
        .a(a_src),
        .b(cmp_b),
        .cmpop(id_ex.cmpop),
        .br_en(ex_mem.br_en)
    );

    // Copy fields
    always_comb begin
        ex_mem.opcode        = id_ex.opcode;
        ex_mem.funct3        = id_ex.funct3;
        ex_mem.funct7        = id_ex.funct7;
        ex_mem.rd_s          = id_ex.rd_s;
        ex_mem.rs1_s         = id_ex.rs1_s;
        ex_mem.rs2_s         = id_ex.rs2_s;
        ex_mem.rs1_v         = a_src;
        ex_mem.rs2_v         = b_src;
        ex_mem.j_imm         = id_ex.j_imm;
        ex_mem.b_imm         = id_ex.b_imm;
        ex_mem.i_imm         = id_ex.i_imm;
        ex_mem.s_imm         = id_ex.s_imm;
        ex_mem.u_imm         = id_ex.u_imm;

        // PHYS
        ex_mem.dest_phys_new = id_ex.dest_phys_new;
        ex_mem.dest_phys_old = id_ex.dest_phys_old;
        ex_mem.dest_arch     = id_ex.dest_arch;

        ex_mem.regf_we       = id_ex.regf_we;
        ex_mem.regfilemux_sel = id_ex.regfilemux_sel;
    end

endmodule
