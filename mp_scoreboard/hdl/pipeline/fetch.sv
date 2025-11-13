/**
 * ============================================================================
 * 取指令阶段 (Fetch Stage)
 * ============================================================================
 * 功能：
 * - 从指令内存取指令
 * - 维护程序计数器 (PC)
 * - 处理分支跳转
 * - 将指令推入指令队列
 *
 * 控制流：
 * - 正常情况：PC = PC + 4
 * - 分支跳转：PC = branch_target (来自 Branch FU)
 * - 队列满：停止取指令 (反压)
 * ============================================================================
 */

module fetch
    import rv32i_types::*;
    (
        input  logic        clk,
        input  logic        rst,

        // ====================================================================
        // 指令内存接口
        // ====================================================================
        output logic [31:0] imem_addr,      // 取指地址
        output logic [3:0]  imem_rmask,     // 读掩码 (始终为 4'b1111)
        input  logic [31:0] imem_rdata,     // 指令数据
        input  logic        imem_resp,      // 内存响应

        // ====================================================================
        // 分支跳转接口 (来自 Branch FU)
        // ====================================================================
        input  logic        branch_taken,   // 分支是否跳转
        input  logic [31:0] branch_target,  // 分支目标地址

        // ====================================================================
        // 指令队列接口
        // ====================================================================
        output logic        iq_enq,         // 入队使能
        output iq_entry_t   iq_enq_data,    // 入队数据
        input  logic        iq_full         // 队列满标志
    );

    // ========================================================================
    // 程序计数器 (PC)
    // ========================================================================
    logic [31:0] pc, next_pc;
    logic [31:0] pc_increment;  // PC 增量：2 (compressed) 或 4 (standard)
    logic [31:0] current_inst;  // 当前指令（处理 2-byte aligned PC）

    // PC 初始值：RISC-V 规范要求从 0x60000000 开始
    localparam logic [31:0] PC_RESET_VALUE = 32'h60000000;

    // 处理 2-byte aligned 但非 4-byte aligned 的 PC
    // Memory 总是返回 4-byte aligned 的 word，所以需要根据 PC[1] 选择正确的部分
    // - 如果 PC[1] = 0: 指令在 imem_rdata[15:0] (可能是 16-bit) 或 imem_rdata[31:0] (32-bit)
    // - 如果 PC[1] = 1: 指令在 imem_rdata[31:16] (只能是 16-bit compressed)
    always_comb begin
        if (pc[1]) begin
            // PC 是 2-byte aligned 但不是 4-byte aligned
            // 指令必定是 16-bit compressed (在高半部分)
            current_inst = {16'h0, imem_rdata[31:16]};
            pc_increment = 32'd2;
        end else begin
            // PC 是 4-byte aligned
            // 检查指令长度：inst[1:0] != 2'b11 表示 16-bit, == 2'b11 表示 32-bit
            current_inst = imem_rdata;
            pc_increment = (imem_rdata[1:0] != 2'b11) ? 32'd2 : 32'd4;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= PC_RESET_VALUE;
        end else if (branch_taken) begin
            // 分支跳转时立即更新 PC，优先级最高
            pc <= branch_target;
        end else if (!iq_full && imem_resp) begin
            // 正常情况：根据指令长度增加 PC (+2 或 +4)
            pc <= pc + pc_increment;
        end
    end

    // ========================================================================
    // 下一个 PC 计算 (组合逻辑)
    // ========================================================================
    always_comb begin
        if (branch_taken) begin
            // 分支跳转：跳转到目标地址
            next_pc = branch_target;
        end else begin
            // 正常情况：PC + 4
            next_pc = pc + 4;
        end
    end

    // ========================================================================
    // 指令内存访问
    // ========================================================================
    // Memory 要求 4-byte aligned 地址，所以强制对齐
    assign imem_addr = {pc[31:2], 2'b00};
    assign imem_rmask = 4'b1111;  // 始终读取完整的 32-bit 字

    // ========================================================================
    // 指令序号追踪 (用于 RVFI 验证)
    // ========================================================================
    logic [63:0] instruction_order;

    always_ff @(posedge clk) begin
        if (rst) begin
            instruction_order <= 64'b0;
        end else if (iq_enq) begin
            instruction_order <= instruction_order + 1;
        end
    end

    // ========================================================================
    // 指令队列入队逻辑
    // ========================================================================
    // 当分支跳转时，不能将已取出的错误指令入队
    assign iq_enq = imem_resp && !iq_full && !branch_taken;

    always_comb begin
        iq_enq_data.inst  = current_inst;  // 使用处理过的指令（考虑 PC[1]）
        iq_enq_data.pc    = pc;
        iq_enq_data.order = instruction_order;
        iq_enq_data.valid = 1'b1;
    end

    // ========================================================================
    // Debug: Fetch 阶段监控
    // ========================================================================
    `ifndef SYNTHESIS
        always @(posedge clk) begin
            if (!rst) begin
                // 监控指令队列满导致的阻塞
                if (iq_full && imem_resp) begin
                    static int stall_cycles = 0;
                    stall_cycles++;
                    if (stall_cycles % 100 == 0) begin
                        $display("[DEBUG FETCH] @%0t IQ full, stalled for %0d cycles", $time, stall_cycles);
                        $display("  PC=%h, waiting inst=%h", pc, imem_rdata);
                    end
                end

                // 监控内存无响应的情况
                if (!iq_full && !imem_resp) begin
                    static int wait_cycles = 0;
                    wait_cycles++;
                    if (wait_cycles % 1000 == 0) begin
                        $display("[DEBUG FETCH] @%0t Waiting for imem_resp for %0d cycles", $time, wait_cycles);
                        $display("  PC=%h", pc);
                    end
                end
            end
        end
    `endif

endmodule : fetch
