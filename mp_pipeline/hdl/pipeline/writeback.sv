module writeback
    import rv32i_types::*;
(
    input  logic                 clk,
    input  logic                 rst,

    input  mem_wb_stage_reg_t    mem_wb,
    input  logic         [31:0]  dmem_rdata,
    input  logic                 dmem_resp,
    input  logic                 freeze_stall,

    // regfilemux output (for forwarding)
    output logic         [31:0]  regfilemux_out,

    // 原本 pipeline 用來寫 regfile 的資訊
    output logic                 regf_we_back,
    output logic         [4:0]   rd_s_back,

    // ========== RVFI interface ==========
    output logic                 rvfi_valid,
    output logic         [63:0]  rvfi_order,
    output logic         [31:0]  rvfi_inst,
    output logic         [4:0]   rvfi_rs1_addr,
    output logic         [4:0]   rvfi_rs2_addr,
    output logic         [31:0]  rvfi_rs1_rdata,
    output logic         [31:0]  rvfi_rs2_rdata,
    output logic         [4:0]   rvfi_rd_addr,
    output logic         [31:0]  rvfi_rd_wdata,
    output logic         [31:0]  rvfi_pc_rdata,
    output logic         [31:0]  rvfi_pc_wdata,
    output logic         [31:0]  rvfi_dmem_addr,
    output logic         [3:0]   rvfi_dmem_rmask,
    output logic         [3:0]   rvfi_dmem_wmask,
    output logic         [31:0]  rvfi_dmem_rdata,
    output logic         [31:0]  rvfi_dmem_wdata
);

    // ================================
    // regfile writeback mux
    // ================================
    logic [31:0] rd_v;

    always_comb begin
        case (mem_wb.regfilemux_sel)
            4'b0001: rd_v = {31'b0, mem_wb.br_en};
            4'b0010: rd_v = mem_wb.u_imm;
            4'b0000: rd_v = mem_wb.alu_out;
            4'b0100: rd_v = mem_wb.pc + 32'd4;

            // LB
            4'b0101: rd_v = {{24{dmem_rdata[ 7 + 8*mem_wb.dmem_addr[1:0] ]}},
                             dmem_rdata[8*mem_wb.dmem_addr[1:0] +: 8]};
            // LBU
            4'b0110: rd_v = {24'b0,
                             dmem_rdata[8*mem_wb.dmem_addr[1:0] +: 8]};
            // LH
            4'b0111: rd_v = {{16{dmem_rdata[15 + 16*mem_wb.dmem_addr[1] ]}},
                             dmem_rdata[16*mem_wb.dmem_addr[1] +: 16]};
            // LHU
            4'b1000: rd_v = {16'b0,
                             dmem_rdata[16*mem_wb.dmem_addr[1] +: 16]};
            // LW
            4'b0011: rd_v = dmem_rdata;

            default: rd_v = 32'd0;
        endcase
    end

    assign regfilemux_out = rd_v;

    // regfile write enable（architectural）
    always_comb begin
        if (mem_wb.opcode == op_load)
            regf_we_back = dmem_resp ? 1'b1 : 1'b0;
        else if (mem_wb.opcode inside {op_br, op_store})
            regf_we_back = 1'b0;
        else
            regf_we_back = mem_wb.regf_we;
    end

    assign rd_s_back = mem_wb.rd_s;

    // ================================
    // RVFI: order counter
    // ================================
    logic [63:0] order_q;

    // 這邊用「乾淨版本」的 commit 判斷，避免 X
    logic commit_raw;
    logic commit;

    assign commit_raw = mem_wb.valid && !freeze_stall;
    // 使用 === 把 X/Z 當成 0
    assign commit     = (commit_raw === 1'b1);

    always_ff @(posedge clk) begin
        if (rst) begin
            order_q    <= 64'd0;
            rvfi_valid <= 1'b0;
        end
        else begin
            if (commit) begin
                rvfi_valid <= 1'b1;
                order_q    <= order_q + 64'd1;
            end
            else begin
                rvfi_valid <= 1'b0;
            end
        end
    end

    assign rvfi_order = order_q;

    // ================================
    // RVFI: basic info
    // ================================
    assign rvfi_inst      = mem_wb.inst;
    assign rvfi_rs1_addr  = mem_wb.rs1_s;
    assign rvfi_rs2_addr  = mem_wb.rs2_s;
    assign rvfi_rs1_rdata = mem_wb.rs1_v;
    assign rvfi_rs2_rdata = mem_wb.rs2_v;

    // 若這條指令不寫 rd，就讓 rvfi_rd_addr/rvfi_rd_wdata 都是 0
    assign rvfi_rd_addr  = regf_we_back ? mem_wb.rd_s : 5'd0;
    assign rvfi_rd_wdata = regf_we_back ? rd_v        : 32'd0;

    assign rvfi_pc_rdata = mem_wb.pc;

    // ================================
    // RVFI: next PC（考慮 branch/jump）
    // ================================
    logic [31:0] pc_next;

    always_comb begin
        pc_next = mem_wb.pc + 32'd4;  // default: sequential

        if (mem_wb.opcode inside {op_jal, op_jalr}) begin
            pc_next = mem_wb.alu_out & 32'hffff_fffe;
        end
        else if (mem_wb.opcode == op_br && mem_wb.br_en) begin
            pc_next = mem_wb.alu_out;
        end
    end

    assign rvfi_pc_wdata = pc_next;

    // ================================
    // RVFI: memory interface
    // ================================
    assign rvfi_dmem_addr  = mem_wb.dmem_addr;
    assign rvfi_dmem_rmask = mem_wb.dmem_rmask;
    assign rvfi_dmem_wmask = mem_wb.dmem_wmask;

    // 對於 load，rdata 來自 dmem_rdata；store 則主要看 wdata
    assign rvfi_dmem_rdata = dmem_rdata;
    assign rvfi_dmem_wdata = mem_wb.dmem_wdata;

endmodule
