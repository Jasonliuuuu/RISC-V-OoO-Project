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
    input  logic flush_pipeline,

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
    // 1. Valid and PC assignment
    // ----------------------------------------
    assign id_ex.pc    = if_id.pc;
    // Flush in-flight instruction when branch/jump detected
    assign id_ex.valid = flush_pipeline ? 1'b0 : if_id.valid;
    // Propagate speculative flag (will be overridden in cpu.sv pipeline register)
    assign id_ex.is_speculative = if_id.is_speculative;


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
    // 3. Basic decode fields from LATCHED instruction (for PRF lookup)
    // ----------------------------------------
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1_s;
    logic [4:0] rs2_s;
    logic [4:0] rd_s;

    assign opcode = inst_dec[6:0];
    assign funct3 = inst_dec[14:12];
    assign funct7 = inst_dec[31:25];
    assign rs1_s  = inst_dec[19:15];
    assign rs2_s  = inst_dec[24:20];
    assign rd_s   = inst_dec[11:7];

    // CURRENT instruction fields (for decode logic - NO DELAY)
    logic [6:0] curr_opcode;
    logic [2:0] curr_funct3;
    logic [6:0] curr_funct7;
    
    assign curr_opcode = imem_rdata_id[6:0];
    assign curr_funct3 = imem_rdata_id[14:12];
    assign curr_funct7 = imem_rdata_id[31:25];

    // ----------------------------------------
    // 4. Assign architectural indices
    // ----------------------------------------
    always_comb begin
        if (flush_pipeline) begin
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
        // Use CURRENT instruction for architectural indices
        id_ex.rs1_arch      = imem_rdata_id[19:15];
        id_ex.rs2_arch      = imem_rdata_id[24:20];
        id_ex.dest_arch     = imem_rdata_id[11:7];
    end
    // ----------------------------------------
    // 6. PRF value → decode pipeline
    // ----------------------------------------
    always_comb begin
        id_ex.rs1_v = rs1_val;
        id_ex.rs2_v = rs2_val;
        
        // Debug decode for specific PCs that have shadow rs2 errors
        if (if_id.pc == 32'hdb0737f0 || if_id.pc == 32'hdb0737f8) begin
            $display("[DECODE] PC=0x%h: imem[24:20]=%0d rs2_arch=%0d rs2_phys=%0d rs2_val(from PRF)=0x%h → id_ex.rs2_v=0x%h",
                     if_id.pc, imem_rdata_id[24:20], id_ex.rs2_arch, rs2_phys, rs2_val, id_ex.rs2_v);
        end
    end

    // ----------------------------------------
    // 6. Immediates calculation
    // ----------------------------------------
    always_comb begin
        // Always use CURRENT instruction (no flushing logic for these)
        id_ex.opcode = imem_rdata_id[6:0];
        id_ex.funct3 = imem_rdata_id[14:12];
        id_ex.funct7 = imem_rdata_id[31:25];

        id_ex.i_imm = {{21{imem_rdata_id[31]}}, imem_rdata_id[30:20]};
        id_ex.s_imm = {{21{imem_rdata_id[31]}}, imem_rdata_id[30:25], imem_rdata_id[11:7]};
        id_ex.b_imm = {{20{imem_rdata_id[31]}}, imem_rdata_id[7], imem_rdata_id[30:25],
                       imem_rdata_id[11:8], 1'b0};
        id_ex.u_imm = {imem_rdata_id[31:12], 12'h000};
        id_ex.j_imm = {{12{imem_rdata_id[31]}}, imem_rdata_id[19:12],
                       imem_rdata_id[20], imem_rdata_id[30:21], 1'b0};
    end

    // CRITICAL: Propagate instruction for RVFI/Debug
    assign id_ex.inst = imem_rdata_id;

    // ----------------------------------------
    // 8. imm_out selection - use CURRENT opcode
    // ----------------------------------------
    always_comb begin
        unique case (curr_opcode)
            op_lui: begin
                id_ex.imm_out = id_ex.u_imm;
            end
            op_auipc: begin
                id_ex.imm_out = id_ex.u_imm;
            end
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
    // 9. ALU operation decode - use CURRENT opcode/funct
    // ----------------------------------------
    always_comb begin
        unique case (curr_opcode)
            op_lui  : id_ex.alu_op = alu_add;  // LUI: pass through
            op_auipc: id_ex.alu_op = alu_add;  // AUIPC: pc + imm
            op_imm  : begin
                unique case (curr_funct3)
                    3'b000: id_ex.alu_op = alu_add;   // ADDI
                    3'b100: id_ex.alu_op = alu_xor;   // XORI
                    3'b110: id_ex.alu_op = alu_or;    // ORI
                    3'b111: id_ex.alu_op = alu_and;   // ANDI
                    3'b001: id_ex.alu_op = alu_sll;   // SLLI
                    3'b101: begin
                        if (curr_funct7[5]) id_ex.alu_op = alu_sra;  // SRAI
                        else                id_ex.alu_op = alu_srl;  // SRLI
                    end
                    // SLTI/SLTIU handled by CMP + MUX, ALU op doesn't matter
                    default: id_ex.alu_op = alu_add;
                endcase
            end
            op_reg  : begin
                unique case (curr_funct3)
                    3'b000: begin
                        if (curr_funct7[5]) id_ex.alu_op = alu_sub;  // SUB
                        else                id_ex.alu_op = alu_add;  // ADD
                    end
                    3'b100: id_ex.alu_op = alu_xor;   // XOR
                    3'b110: id_ex.alu_op = alu_or;    // OR
                    3'b111: id_ex.alu_op = alu_and;   // AND
                    3'b001: id_ex.alu_op = alu_sll;   // SLL
                    3'b101: begin
                        if (curr_funct7[5]) id_ex.alu_op = alu_sra;  // SRA
                        else                id_ex.alu_op = alu_srl;  // SRL
                    end
                    // SLT/SLTU handled by CMP + MUX
                    default: id_ex.alu_op = alu_add;
                endcase
            end
            default: id_ex.alu_op = alu_add;
        endcase
    end

    // ----------------------------------------
    // 10. ALU operand mux - use CURRENT opcode
    // ----------------------------------------
    always_comb begin
        unique case(curr_opcode)
            op_auipc,
            op_br,
            op_jal:  id_ex.alu_m1_sel = 1'b1;
            default: id_ex.alu_m1_sel = 1'b0;
        endcase
    end

    assign id_ex.alu_m2_sel =
        (curr_opcode inside {op_auipc, op_store, op_load, op_imm, op_jalr, op_br, op_jal}) ? 1'b1 : 1'b0;

    // ----------------------------------------
    // 11. cmp mux - use CURRENT opcode
    // ----------------------------------------
    // cmp_sel: 1 = use immediate, 0 = use rs2
    assign id_ex.cmp_sel =
        (curr_opcode == op_br) ? 1'b0 :          // Branches use rs2
        (curr_opcode == op_jalr) ? 1'b1 :        // JALR uses immediate
        (curr_opcode == op_imm && (curr_funct3 == slt || curr_funct3 == sltu)) ? 1'b1 :  // SLTI/SLTIU use immediate
        (curr_opcode == op_reg && (curr_funct3 == slt || curr_funct3 == sltu)) ? 1'b0 :  // SLT/SLTU use rs2
        1'b0;  // Default

    // ----------------------------------------
    // 12. regfile write enable - use CURRENT opcode
    // ----------------------------------------
    always_comb begin
        if (curr_opcode inside {op_br, op_store})
            id_ex.regf_we = 1'b0;
        else
            id_ex.regf_we = 1'b1;
    end

    // 12. regfile mux selection - use CURRENT opcode
    // ----------------------------------------
    always_comb begin
        casez (curr_opcode)
            op_lui:     id_ex.regfilemux_sel = regfilemux::u_imm;
            op_auipc:   id_ex.regfilemux_sel = regfilemux::alu_out; // AUIPC result from ALU
            op_jal:     id_ex.regfilemux_sel = regfilemux::pc_plus4;
            op_jalr:    id_ex.regfilemux_sel = regfilemux::pc_plus4;
            op_load: begin
                // Map funct3 to correct load type
                unique case (curr_funct3)
                    3'b000: id_ex.regfilemux_sel = regfilemux::lb;   // LB
                    3'b001: id_ex.regfilemux_sel = regfilemux::lh;   // LH
                    3'b010: id_ex.regfilemux_sel = regfilemux::lw;   // LW
                    3'b100: id_ex.regfilemux_sel = regfilemux::lbu;  // LBU
                    3'b101: id_ex.regfilemux_sel = regfilemux::lhu;  // LHU
                    default: id_ex.regfilemux_sel = regfilemux::lw;  // Default to LW
                endcase
            end
            op_imm: begin
                if (curr_funct3 == slt || curr_funct3 == sltu)
                    id_ex.regfilemux_sel = regfilemux::br_en;
                else
                    id_ex.regfilemux_sel = regfilemux::alu_out;
            end
            op_reg: begin
                if (curr_funct3 == slt || curr_funct3 == sltu)
                    id_ex.regfilemux_sel = regfilemux::br_en;
                else
                    id_ex.regfilemux_sel = regfilemux::alu_out;
            end
            default:    id_ex.regfilemux_sel = regfilemux::alu_out;
        endcase
    end

    // 13. cmpop decode
    // ----------------------------------------
    always_comb begin
        if (curr_opcode == op_br) begin
            id_ex.cmpop = branch_funct3_t'(curr_funct3);
        end
        else if ((curr_opcode == op_imm || curr_opcode == op_reg) && (curr_funct3 == slt)) begin
            id_ex.cmpop = blt;
        end
        else if ((curr_opcode == op_imm || curr_opcode == op_reg) && (curr_funct3 == sltu)) begin
            id_ex.cmpop = bltu;
        end
        else begin
            id_ex.cmpop = beq; // default
        end
    end

endmodule
