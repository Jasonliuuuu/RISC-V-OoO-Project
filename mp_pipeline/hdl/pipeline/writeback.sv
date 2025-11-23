module writeback
    import rv32i_types::*;
(
    input  logic                 clk,
    input  logic                 rst,

    input  mem_wb_stage_reg_t    mem_wb,
    input  logic         [31:0]  dmem_rdata,
    input  logic                 dmem_resp,
    input  logic                 freeze_stall,
    input  logic                 flush_delayed,  // NEW: check flush at WB stage

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

    // Mux for output to regfile and RVFI
    assign regfilemux_out = rd_v;

    // Debug specific PC
    always @(posedge clk) begin
        if (mem_wb.valid && mem_wb.pc == 32'h60000080) begin
            $display("[WB] PC=0x%h, opcode=0x%02x, regfilemux_sel=%0d", 
                     mem_wb.pc, mem_wb.opcode, mem_wb.regfilemux_sel);
            $display("     alu_out=0x%h, u_imm=0x%h, pc=0x%h", 
                     mem_wb.alu_out, mem_wb.u_imm, mem_wb.pc);
            $display("     rd_v(result)=0x%h", rd_v);
        end
    end


    // Extract opcode directly from instruction to avoid timing issues
    logic [6:0] wb_opcode;
    assign wb_opcode = mem_wb.inst[6:0];

    // regfile write enable（architectural）
    always_comb begin
        if (wb_opcode == op_load)
            regf_we_back = dmem_resp ? 1'b1 : 1'b0;
        else if (wb_opcode inside {op_br, op_store})
            regf_we_back = 1'b0;
        else
            regf_we_back = mem_wb.regf_we;
    end

    assign rd_s_back = mem_wb.dest_arch;

    // ================================
    // RVFI: Simple Registered Outputs
    // ================================
    // RVFI Output Registers
    // ================================
    logic                rvfi_valid_reg;
    logic [63:0]         rvfi_order_reg;
    logic [31:0]         rvfi_inst_reg;
    logic [4:0]          rvfi_rs1_addr_reg;
    logic [4:0]          rvfi_rs2_addr_reg;
    logic [31:0]         rvfi_rs1_rdata_reg;
    logic [31:0]         rvfi_rs2_rdata_reg;
    logic [4:0]          rvfi_rd_addr_reg;
    logic [31:0]         rvfi_rd_wdata_reg;
    logic [31:0]         rvfi_pc_rdata_reg;
    logic [31:0]         rvfi_pc_wdata_reg;
    logic [31:0]         rvfi_dmem_addr_reg;
    logic [3:0]          rvfi_dmem_rmask_reg;
    logic [3:0]          rvfi_dmem_wmask_reg;
    logic [31:0]         rvfi_dmem_rdata_reg;
    // Order counter
    logic [63:0] order_q;

    
    // ================================
    // RVFI: Combinational Pattern (from main branch)
    // ================================
    // Key insight: RVFI signals should be COMBINATIONAL ASSIGNS
    // Only order counter needs to be registered
    // Commit decision is purely combinational based on mem_wb input
    // ================================
    
    logic commit;
    
    // Commit decision - combinational
    always_comb begin
        if ((~freeze_stall) && (mem_wb.valid) && (!mem_wb.is_speculative)) begin
            commit = 1'b1;
        end
        else begin
            commit = 1'b0;
        end
    end
    
    // Debug: Show commit decisions for critical region
    always @(posedge clk) begin
        if (mem_wb.valid && mem_wb.pc >= 32'hdb138de0 && mem_wb.pc <= 32'hdb138e10) begin
            $display("[WB @%0t] PC=0x%h: valid=%b is_spec=%b freeze=%b → COMMIT=%b (order will be %0d)",
                     $time, mem_wb.pc, mem_wb.valid, mem_wb.is_speculative, 
                     freeze_stall, commit, order_q);
        end
        
        if (commit && order_q >= 64'd20 && order_q <= 64'd30) begin
            $display("[WB @%0t] ✅ COMMITTING order=%0d PC=0x%h (is_spec was %b)",
                     $time, order_q, mem_wb.pc, mem_wb.is_speculative);
        end
    end
    
    // Order counter - sequential (only registered part)
    always_ff @(posedge clk) begin
        if (rst) begin
            order_q <= 64'd0;
        end
        else if (commit) begin
            order_q <= order_q + 64'd1;
        end
        else begin
            order_q <= order_q;
        end
    end
    
    // ================================
    // RVFI Output Signals - ALL COMBINATIONAL
    // ================================
    // These are output ports, not internal signals.
    // The original code declared them as outputs, so we don't redeclare them as 'logic'.
    // The new code snippet provided them as 'logic' declarations, which implies they were meant to be internal wires
    // driving the output ports. However, to maintain the existing output port structure,
    // we will directly assign to the output ports.
    
    // PC next calculation - combinational
    always_comb begin
        if ((mem_wb.opcode == op_br) && (mem_wb.br_en == 1'b1)) begin
            rvfi_pc_wdata = mem_wb.alu_out;
        end
        else if (mem_wb.opcode == op_jal) begin
            rvfi_pc_wdata = mem_wb.alu_out;
        end
        else if (mem_wb.opcode == op_jalr) begin
            rvfi_pc_wdata = mem_wb.alu_out & 32'hfffffffe;
        end
        else begin
            rvfi_pc_wdata = mem_wb.pc + 32'd4;
        end
    end
    
    // Zero out unused registers - combinational
    assign rvfi_rs1_addr = (mem_wb.opcode inside {op_jalr, op_br, op_load, op_store, op_reg, op_imm}) ? mem_wb.rs1_arch : 5'b0;
    assign rvfi_rs2_addr = (mem_wb.opcode inside {op_br, op_store, op_reg}) ? mem_wb.rs2_arch : 5'b0;
    assign rvfi_rs1_rdata = (mem_wb.opcode inside {op_jalr, op_br, op_load, op_store, op_reg, op_imm}) ? mem_wb.rs1_v : 32'b0;
    assign rvfi_rs2_rdata = (mem_wb.opcode inside {op_br, op_store, op_reg}) ? mem_wb.rs2_v : 32'b0;
    assign rvfi_rd_addr = (mem_wb.opcode != op_store && mem_wb.opcode != op_br) ? mem_wb.dest_arch : 5'b0;
    
    // All RVFI outputs - combinational assigns  
    assign rvfi_valid = commit;
    assign rvfi_order = order_q;
    assign rvfi_inst = mem_wb.inst;
    // CRITICAL: Force rd_wdata to 0 when writing to x0 (RVFI spec requirement)
    assign rvfi_rd_wdata = (rvfi_rd_addr == 5'd0) ? 32'd0 : rd_v;
    assign rvfi_pc_rdata = mem_wb.pc;
    assign rvfi_dmem_addr = mem_wb.dmem_addr;
    
    // Debug RVFI output for problematic orders
    always_comb begin
        if (commit && (order_q == 60 || order_q == 62)) begin
            $display("[WRITEBACK] order=%0d PC=0x%h opcode=0x%02x valid=%b is_spec=%b",
                     order_q, mem_wb.pc, mem_wb.opcode, mem_wb.valid, mem_wb.is_speculative);
            $display("            rs2_arch=%0d rs2_v=0x%h rvfi_rs2_addr=%0d rvfi_rs2_rdata=0x%h",
                     mem_wb.rs2_arch, mem_wb.rs2_v, rvfi_rs2_addr, rvfi_rs2_rdata);
            $display("            Check: opcode inside {op_br,op_store,op_reg}? = %b", 
                     mem_wb.opcode inside {op_br, op_store, op_reg});
        end
    end
    assign rvfi_dmem_rmask = mem_wb.dmem_rmask;
    assign rvfi_dmem_wmask = mem_wb.dmem_wmask;
    assign rvfi_dmem_rdata = dmem_rdata;
    assign rvfi_dmem_wdata = mem_wb.dmem_wdata;

endmodule
