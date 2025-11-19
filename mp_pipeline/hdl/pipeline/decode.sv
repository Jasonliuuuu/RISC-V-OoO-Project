module decode
    import rv32i_types::*;
(
    input  logic clk,
    input  logic rst,

    // ============================
    // From IF/ID
    // ============================
    input  logic [31:0]        imem_rdata_id,
    input  if_id_stage_reg_t   if_id,
    input  logic               imem_resp_id,

    // ============================
    // Pipeline control
    // ============================
    input  logic stall_signal,
    input  logic freeze_stall,
    input  logic flushing_inst,

    // ============================
    // From rename_unit (Option A)
    // ============================
    input  logic [5:0] rs1_phys,
    input  logic [5:0] rs2_phys,
    input  logic [5:0] dest_phys_new,
    input  logic [5:0] dest_phys_old,

    // ============================
    // From PRF (Option A)
    // ============================
    input  logic [31:0] rs1_val,
    input  logic [31:0] rs2_val,

    // ============================
    // Output to ID/EX
    // ============================
    output id_ex_stage_reg_t id_ex
);

    // ----------------------------------------
    // 1. Valid
    // ----------------------------------------
    assign id_ex.valid = (!flushing_inst) && if_id.valid && imem_resp_id;
    assign id_ex.pc    = if_id.pc;

    // ----------------------------------------
    // 2. Latch instruction
    // ----------------------------------------
    logic [31:0] inst_dec;

    always_ff @(posedge clk) begin
        if (rst)
            inst_dec <= 32'd0;
        else if (freeze_stall || stall_signal)
            inst_dec <= inst_dec; // hold
        else
            inst_dec <= imem_rdata_id;
    end

    // ----------------------------------------
    // 3. Basic decode fields
    // ----------------------------------------
    logic [6:0] opcode = inst_dec[6:0];
    logic [2:0] funct3 = inst_dec[14:12];
    logic [6:0] funct7 = inst_dec[31:25];

    logic [4:0] rs1_s  = inst_dec[19:15];
    logic [4:0] rs2_s  = inst_dec[24:20];
    logic [4:0] rd_s   = inst_dec[11:7];

    // ----------------------------------------
    // 4. Assign architectural indices
    // ----------------------------------------
    always_comb begin
        if (flushing_inst) begin
            id_ex.rs1_s = '0;
            id_ex.rs2_s = '0;
            id_ex.rd_s  = '0;
        end
        else begin
            id_ex.rs1_s = rs1_s;
            id_ex.rs2_s = rs2_s;
            id_ex.rd_s  = rd_s;
        end
    end

    // ----------------------------------------
    // 5. Physical register mapping (rename → decode)
    // ----------------------------------------
    always_comb begin
        id_ex.rs1_phys      = rs1_phys;
        id_ex.rs2_phys      = rs2_phys;
        id_ex.dest_phys_new = dest_phys_new;
        id_ex.dest_phys_old = dest_phys_old;
        id_ex.dest_arch     = rd_s;
    end

    // ----------------------------------------
    // 6. PRF value → decode pipeline
    // ----------------------------------------
    always_comb begin
        id_ex.rs1_v = rs1_val;
        id_ex.rs2_v = rs2_val;
    end

    // ----------------------------------------
    // 7. Immediate generation
    // ----------------------------------------
    always_comb begin
        if (flushing_inst) begin
            id_ex.opcode = '0;
            id_ex.funct3 = '0;
            id_ex.funct7 = '0;
            id_ex.i_imm  = '0;
            id_ex.s_imm  = '0;
            id_ex.b_imm  = '0;
            id_ex.u_imm  = '0;
            id_ex.j_imm  = '0;
        end
        else begin
            id_ex.opcode = opcode;
            id_ex.funct3 = funct3;
            id_ex.funct7 = funct7;

            id_ex.i_imm = {{21{inst_dec[31]}}, inst_dec[30:20]};
            id_ex.s_imm = {{21{inst_dec[31]}}, inst_dec[30:25], inst_dec[11:7]};
            id_ex.b_imm = {{20{inst_dec[31]}}, inst_dec[7], inst_dec[30:25],
                           inst_dec[11:8], 1'b0};
            id_ex.u_imm = {inst_dec[31:12], 12'h000};
            id_ex.j_imm = {{12{inst_dec[31]}}, inst_dec[19:12],
                           inst_dec[20], inst_dec[30:21], 1'b0};
        end
    end

    // ----------------------------------------
    // 8. imm_out selection (same as your original)
    // ----------------------------------------
    always_comb begin
        unique case (opcode)
            op_lui, op_auipc: id_ex.imm_out = id_ex.u_imm;
            op_jal          : id_ex.imm_out = id_ex.j_imm;
            op_jalr         : id_ex.imm_out = id_ex.i_imm;
            op_br           : id_ex.imm_out = id_ex.b_imm;
            op_load         : id_ex.imm_out = id_ex.i_imm;
            op_store        : id_ex.imm_out = id_ex.s_imm;
            op_imm          : id_ex.imm_out = id_ex.i_imm;
            default         : id_ex.imm_out = 32'd0;
        endcase
    end

    // ----------------------------------------
    // 9. ALU operand mux
    // ----------------------------------------
    always_comb begin
        unique case(opcode)
            op_auipc,
            op_br,
            op_jal:  id_ex.alu_m1_sel = 1'b1;
            default: id_ex.alu_m1_sel = 1'b0;
        endcase
    end

    assign id_ex.alu_m2_sel =
        (opcode inside {op_store, op_load, op_imm, op_jalr}) ? 1'b1 : 1'b0;

    // ----------------------------------------
    // 10. cmp mux
    // ----------------------------------------
    assign id_ex.cmp_sel =
        (opcode == op_br) ? 1'b0 :
        (opcode == op_jalr) ? 1'b1 :
        1'b0;

    assign id_ex.cmpop = funct3;

    // ----------------------------------------
    // 11. regfile mux (same as original)
    // ----------------------------------------
    always_comb begin
        if (opcode inside {op_br, op_store})
            id_ex.regf_we = 1'b0;
        else
            id_ex.regf_we = 1'b1;
    end

    always_comb begin
        id_ex.regfilemux_sel = regfilemux::regfilemux_sel_t'(
            (opcode == op_lui   ) ? regfilemux::u_imm :
            (opcode == op_jal   ) ? regfilemux::pc_plus4 :
            (opcode == op_jalr  ) ? regfilemux::pc_plus4 :
            (opcode == op_load  ) ? funct3 :
            regfilemux::alu_out
        );
    end

endmodule
