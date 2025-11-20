module memory
    import rv32i_types::*;
(
    input  ex_mem_stage_reg_t ex_mem,

    input  mem_wb_stage_reg_t mem_wb_now,
    input  logic freeze_stall,
    output mem_wb_stage_reg_t mem_wb,

    output logic [31:0] dmem_addr,
    output logic [3:0]  dmem_rmask,
    output logic [3:0]  dmem_wmask,
    output logic [31:0] dmem_wdata,

    output logic mem_wb_br_en,
    output logic [31:0] mem_wb_alu_out,
    output logic [31:0] mem_wb_u_imm,

    output logic br_en_out,
    output logic [31:0] branch_new_address,
    output logic flush_pipeline
);

    assign mem_wb_alu_out = ex_mem.alu_out;
    assign mem_wb_br_en   = ex_mem.br_en;
    assign mem_wb_u_imm   = ex_mem.u_imm;

    // load/store calculate address
    always_comb begin
        mem_wb.dmem_rmask = 4'b0;
        mem_wb.dmem_addr  = 32'd0;
        mem_wb.dmem_wmask = 4'b0;
        mem_wb.dmem_wdata = 32'd0;

        if (ex_mem.opcode == op_load) begin
            mem_wb.dmem_addr = ex_mem.rs1_v + ex_mem.i_imm;

            unique case (ex_mem.funct3)
                lb, lbu: mem_wb.dmem_rmask = 4'b0001 << mem_wb.dmem_addr[1:0];
                lh, lhu: mem_wb.dmem_rmask = 4'b0011 << mem_wb.dmem_addr[1:0];
                lw:      mem_wb.dmem_rmask = 4'b1111;
            endcase
        end
        else if (ex_mem.opcode == op_store) begin
            mem_wb.dmem_addr = ex_mem.rs1_v + ex_mem.s_imm;

            unique case (ex_mem.funct3)
                sb: mem_wb.dmem_wmask = 4'b0001 << mem_wb.dmem_addr[1:0];
                sh: mem_wb.dmem_wmask = 4'b0011 << mem_wb.dmem_addr[1:0];
                sw: mem_wb.dmem_wmask = 4'b1111;
            endcase

            unique case (ex_mem.funct3)
                sb: mem_wb.dmem_wdata[8*mem_wb.dmem_addr[1:0] +: 8] = ex_mem.rs2_v[7:0];
                sh: mem_wb.dmem_wdata[16*mem_wb.dmem_addr[1]   +:16] = ex_mem.rs2_v[15:0];
                sw: mem_wb.dmem_wdata = ex_mem.rs2_v;
            endcase
        end
    end

    // align output addr
    always_comb begin
        if (freeze_stall) begin
            dmem_addr  = mem_wb_now.dmem_addr & 32'hFFFF_FFFC;
            dmem_rmask = mem_wb_now.dmem_rmask;
            dmem_wmask = mem_wb_now.dmem_wmask;
            dmem_wdata = mem_wb_now.dmem_wdata;
        end else begin
            dmem_addr  = mem_wb.dmem_addr & 32'hFFFF_FFFC;
            dmem_rmask = mem_wb.dmem_rmask;
            dmem_wmask = mem_wb.dmem_wmask;
            dmem_wdata = mem_wb.dmem_wdata;
        end
    end

    // branch control
    always_comb begin
        br_en_out = 
            (ex_mem.opcode inside {op_jal, op_jalr}) ? 1'b1 :
            ((ex_mem.opcode == op_br) && ex_mem.br_en) ? 1'b1 :
            1'b0;
    end

    always_comb begin
        if (ex_mem.opcode inside {op_jal, op_jalr})
            branch_new_address = ex_mem.alu_out & 32'hFFFF_FFFE;
        else if ((ex_mem.opcode == op_br) && ex_mem.br_en)
            branch_new_address = ex_mem.alu_out;
        else
            branch_new_address = 32'd0;
    end

    always_comb begin
        if (ex_mem.valid === 1'b1) begin
            flush_pipeline = (ex_mem.opcode inside {op_jal, op_jalr}) ||
                           ((ex_mem.opcode == op_br) && ex_mem.br_en);
        end
        else begin
            flush_pipeline = 1'b0;
        end
    end

    // fill mem_wb struct
    assign mem_wb.inst  = ex_mem.inst;
    assign mem_wb.pc    = ex_mem.pc;
    // CRITICAL: Flush mem_wb.valid to prevent flushed instructions from committing
    // When flush_pipeline is active, instructions that reach WB should not commit
    assign mem_wb.valid = flush_pipeline ? 1'b0 : ex_mem.valid;
    assign mem_wb.opcode = ex_mem.opcode;

    assign mem_wb.rs1_s = ex_mem.rs1_s;
    assign mem_wb.rs2_s = ex_mem.rs2_s;
    assign mem_wb.rd_s  = ex_mem.rd_s;

    assign mem_wb.rs1_v = ex_mem.rs1_v;
    assign mem_wb.rs2_v = ex_mem.rs2_v;

    assign mem_wb.j_imm = ex_mem.j_imm;
    assign mem_wb.b_imm = ex_mem.b_imm;
    assign mem_wb.i_imm = ex_mem.i_imm;
    assign mem_wb.u_imm = ex_mem.u_imm;

    assign mem_wb.br_en = ex_mem.br_en;
    assign mem_wb.alu_out = ex_mem.alu_out;

    assign mem_wb.regf_we = ex_mem.regf_we;
    assign mem_wb.regfilemux_sel = ex_mem.regfilemux_sel;

    // PHYS
    assign mem_wb.rs1_arch      = ex_mem.rs1_arch;
    assign mem_wb.rs2_arch      = ex_mem.rs2_arch;
    assign mem_wb.rs1_phys      = ex_mem.rs1_phys;
    assign mem_wb.rs2_phys      = ex_mem.rs2_phys;
    assign mem_wb.dest_phys_new = ex_mem.dest_phys_new;
    assign mem_wb.dest_phys_old = ex_mem.dest_phys_old;
    assign mem_wb.dest_arch     = ex_mem.dest_arch;

endmodule
