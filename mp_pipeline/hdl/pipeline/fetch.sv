module fetch 
    import rv32i_types::*;

(
    input logic clk,
    input logic rst,
    //========== BNEZ / JUMP ==========
    input logic br_en,
    input logic [31:0]  branch_pc,
    //========== I-mem 介面回傳 ==========
    input logic [31:0]  imem_rdata,
    input  logic        imem_resp,
    // ========== Pipeline control ==========
    input  logic        stall_signal,
    input  logic        freeze_stall,
    input  logic        flushing_inst,  
    // A flush determined by a later pipeline stage (misfetch or branch/jump).
    // ========== The requestment to I-mem ==========
    output logic [31:0] imem_addr,
    output logic [3:0]  imem_rmask,
    // ========== 給decode的IF/ID ====================
    output var if_id_stage_reg_t  if_id_reg_before, 
    output logic [31:0] imem_rdata_id, 
    output logic        imem_resp_id
    
);
    logic ce_ifid; //clock enable
    assign ce_ifid = !(freeze_stall || stall_signal);

    logic [31:0] pc;
    //read signal always 1
    assign imem_rmask = 4'b1111;
    always_ff@(posedge clk) begin
        if(rst) begin
            pc <= 32'h60000000;
        end
        else begin
             if(freeze_stall || stall_signal) begin
                pc <= pc;
             end
             else begin
                if(br_en) begin
                    pc <= branch_pc;
                end
                else
                    pc <= pc + 32'd4;
            end
        end
    end
//*****fixing the imem_resp and imem_address*******

    always_comb begin
        if(br_en) begin
            imem_addr = branch_pc;
        end
        else begin
            imem_addr = pc;
        end
    end

//******** IF -> ID: pc /valid *************
    always_ff @(posedge clk) begin
        if (rst) begin 
            if_id_reg_before.pc <= '0; 
            if_id_reg_before.valid <= 1'b0; // 表示這拍是bubble
        end
        else if (flushing_inst) begin
            if_id_reg_before.valid <= 1'b0; //flush 注入bubble, remain the pc
        end
        else if (ce_ifid) begin
            if_id_reg_before.pc <= pc; //傳送現在指令的PC
            if_id_reg_before.valid <= imem_resp; //這拍 I-mem 確認有效才為 1
        end
    end
// =============== IF -> ID inst/resp ================
    //把指令與有效為打一拍 條件與上面一致
    // Flush 時把inst -> NOP, resp -> 0, 避免鬼指令
    always_ff @(posedge clk) begin
        if (rst) begin
            imem_rdata_id <= 32'h0000_0013; //NOP: ADDI x0, x0, 0
            imem_resp_id <= 1'b0; 
        end
        else if (flushing_inst) begin
            imem_rdata_id <= 32'h0000_0013; //無害化
            imem_resp_id <= 1'b0; 
        end
        else if (ce_ifid) begin
            imem_rdata_id <= imem_rdata; 
            imem_resp_id <= imem_resp; 
        end
        //else: HOLD
    end
    


    

   


endmodule

