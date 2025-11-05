/**
 * ============================================================================
 * CPU 顶层模块 - Scoreboard 架构处理器
 * ============================================================================
 * 架构：Scoreboard + 多功能单元 (Multiple Functional Units)
 *
 * 组件：
 * - Fetch 阶段：取指令并推入指令队列
 * - Instruction Queue：缓冲指令
 * - Scoreboard：Issue 逻辑、冒险检测、状态管理
 * - 功能单元：2×ALU, 1×MUL, 1×DIV, 1×Load/Store, 1×Branch
 * - Common Data Bus：仲裁多个 FU 的写回
 * - Register File：32 个通用寄存器
 *
 * 特点：
 * - 指令可以乱序完成 (Out-of-Order Completion)
 * - 顺序发射 (In-Order Issue)
 * - 动态调度 (Dynamic Scheduling)
 * - 结构冒险：等待空闲 FU
 * - 数据冒险：Scoreboard 检测并停顿
 * ============================================================================
 */

module cpu
    import rv32i_types::*;
    (
        input  logic        clk,
        input  logic        rst,

        // ====================================================================
        // 指令内存接口
        // ====================================================================
        output logic [31:0] imem_addr,      // 指令地址
        output logic [3:0]  imem_rmask,     // 读掩码
        input  logic [31:0] imem_rdata,     // 指令数据
        input  logic        imem_resp,      // 内存响应

        // ====================================================================
        // 数据内存接口
        // ====================================================================
        output logic [31:0] dmem_addr,      // 数据地址
        output logic [3:0]  dmem_rmask,     // 读掩码
        output logic [3:0]  dmem_wmask,     // 写掩码
        input  logic [31:0] dmem_rdata,     // 读数据
        output logic [31:0] dmem_wdata,     // 写数据
        input  logic        dmem_resp       // 内存响应
    );

    // ========================================================================
    // 内部信号声明
    // ========================================================================

    // ------------------------------------------------------------------------
    // 指令队列信号
    // ------------------------------------------------------------------------
    logic       iq_enq, iq_deq, iq_full, iq_empty, iq_flush;
    iq_entry_t  iq_enq_data, iq_deq_data;

    // ------------------------------------------------------------------------
    // 寄存器堆信号
    // ------------------------------------------------------------------------
    logic [4:0]  rf_rs1_addr, rf_rs2_addr, rf_rd_addr;
    logic [31:0] rf_rs1_data, rf_rs2_data, rf_rd_data;
    logic        rf_we;

    // ------------------------------------------------------------------------
    // 功能单元接口 (所有 FU 共 TOTAL_FU 个)
    // ------------------------------------------------------------------------
    fu_interface fu_if [TOTAL_FU] ();

    // ------------------------------------------------------------------------
    // Common Data Bus 信号
    // ------------------------------------------------------------------------
    cdb_entry_t  cdb_data;
    logic        cdb_valid;
    cdb_entry_t  fu_complete_data [TOTAL_FU];
    logic        fu_complete_valid [TOTAL_FU];
    logic        cdb_grant [TOTAL_FU];

    // ------------------------------------------------------------------------
    // 分支跳转信号
    // ------------------------------------------------------------------------
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        flush;

    // ========================================================================
    // 1. Fetch 阶段
    // ========================================================================
    fetch fetch_inst (
        .clk           (clk),
        .rst           (rst),
        .imem_addr     (imem_addr),
        .imem_rmask    (imem_rmask),
        .imem_rdata    (imem_rdata),
        .imem_resp     (imem_resp),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .iq_enq        (iq_enq),
        .iq_enq_data   (iq_enq_data),
        .iq_full       (iq_full)
    );

    // ========================================================================
    // 2. 指令队列
    // ========================================================================
    instruction_queue #(
        .DEPTH(IQ_DEPTH)
    ) iq (
        .clk      (clk),
        .rst      (rst),
        .enq      (iq_enq),
        .enq_data (iq_enq_data),
        .full     (iq_full),
        .deq      (iq_deq),
        .deq_data (iq_deq_data),
        .empty    (iq_empty),
        .flush    (iq_flush)
    );

    // ========================================================================
    // 3. 寄存器堆
    // ========================================================================
    regfile rf (
        .clk     (clk),
        .rst     (rst),
        .regf_we (rf_we),
        .rd_v    (rf_rd_data),
        .rd_s    (rf_rd_addr),
        .rs1_s   (rf_rs1_addr),
        .rs2_s   (rf_rs2_addr),
        .rs1_v   (rf_rs1_data),
        .rs2_v   (rf_rs2_data)
    );

    // 寄存器堆写入来自 CDB
    assign rf_we      = cdb_valid && (cdb_data.rd != 5'b0);
    assign rf_rd_addr = cdb_data.rd;
    assign rf_rd_data = cdb_data.data;

    // ========================================================================
    // 4. Scoreboard 主控制逻辑
    // ========================================================================
    logic flush_out;

    scoreboard #(
        .NUM_FU(TOTAL_FU)
    ) sb (
        .clk         (clk),
        .rst         (rst),
        .iq_data     (iq_deq_data),
        .iq_empty    (iq_empty),
        .iq_deq      (iq_deq),
        .rf_rs1_addr (rf_rs1_addr),
        .rf_rs2_addr (rf_rs2_addr),
        .rf_rs1_data (rf_rs1_data),
        .rf_rs2_data (rf_rs2_data),
        .fu_if       (fu_if),
        .cdb_data    (cdb_data),
        .cdb_valid   (cdb_valid),
        .flush       (flush),
        .flush_out   (flush_out)
    );

    assign iq_flush = flush;

    // ========================================================================
    // 5. 功能单元实例化
    // ========================================================================

    // ------------------------------------------------------------------------
    // 5.1 ALU 功能单元 (2 个)
    // ------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_FU_ALU; i++) begin : gen_fu_alu
            fu_alu fu_alu_inst (
                .clk   (clk),
                .rst   (rst),
                .fu_if (fu_if[i])
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 5.2 乘法器功能单元 (1 个)
    // ------------------------------------------------------------------------
    localparam int IDX_MUL = NUM_FU_ALU;

    fu_multiplier fu_mul_inst (
        .clk   (clk),
        .rst   (rst),
        .fu_if (fu_if[IDX_MUL])
    );

    // ------------------------------------------------------------------------
    // 5.3 除法器功能单元 (1 个)
    // ------------------------------------------------------------------------
    localparam int IDX_DIV = NUM_FU_ALU + NUM_FU_MUL;

    fu_divider fu_div_inst (
        .clk   (clk),
        .rst   (rst),
        .fu_if (fu_if[IDX_DIV])
    );

    // ------------------------------------------------------------------------
    // 5.4 Load/Store 功能单元 (1 个)
    // ------------------------------------------------------------------------
    localparam int IDX_LS = NUM_FU_ALU + NUM_FU_MUL + NUM_FU_DIV;

    fu_load_store fu_ls_inst (
        .clk        (clk),
        .rst        (rst),
        .fu_if      (fu_if[IDX_LS]),
        .dmem_addr  (dmem_addr),
        .dmem_rmask (dmem_rmask),
        .dmem_wmask (dmem_wmask),
        .dmem_rdata (dmem_rdata),
        .dmem_wdata (dmem_wdata),
        .dmem_resp  (dmem_resp)
    );

    // ------------------------------------------------------------------------
    // 5.5 Branch 功能单元 (1 个)
    // ------------------------------------------------------------------------
    localparam int IDX_BR = NUM_FU_ALU + NUM_FU_MUL + NUM_FU_DIV + NUM_FU_LS;

    fu_branch fu_br_inst (
        .clk           (clk),
        .rst           (rst),
        .fu_if         (fu_if[IDX_BR]),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    assign flush = branch_taken;

    // ========================================================================
    // 6. Common Data Bus (CDB) 仲裁器
    // ========================================================================

    // 收集所有 FU 的完成信号
    generate
        for (i = 0; i < TOTAL_FU; i++) begin : gen_cdb_collect
            assign fu_complete_data[i]  = fu_if[i].complete_data;
            assign fu_complete_valid[i] = fu_if[i].complete_valid;
        end
    endgenerate

    common_data_bus #(
        .NUM_FU(TOTAL_FU)
    ) cdb (
        .clk              (clk),
        .rst              (rst),
        .fu_complete      (fu_complete_data),
        .fu_complete_valid(fu_complete_valid),
        .cdb_data         (cdb_data),
        .cdb_valid        (cdb_valid),
        .cdb_grant        (cdb_grant)
    );

    // ========================================================================
    // 7. RVFI 验证接口信号 (连接到外部 monitor)
    // ========================================================================
    // 注意：Scoreboard 架构中指令可能乱序完成
    // RVFI 信号直接来自 CDB

    // 这些信号会被 hvl/rvfi_reference.json 引用
    logic           monitor_valid;
    logic [63:0]    monitor_order;
    logic [31:0]    monitor_inst;
    logic [4:0]     monitor_rs1_addr;
    logic [4:0]     monitor_rs2_addr;
    logic [31:0]    monitor_rs1_rdata;
    logic [31:0]    monitor_rs2_rdata;
    logic [4:0]     monitor_rd_addr;
    logic [31:0]    monitor_rd_wdata;
    logic [31:0]    monitor_pc_rdata;
    logic [31:0]    monitor_pc_wdata;
    logic [31:0]    monitor_mem_addr;
    logic [3:0]     monitor_mem_rmask;
    logic [3:0]     monitor_mem_wmask;
    logic [31:0]    monitor_mem_rdata;
    logic [31:0]    monitor_mem_wdata;

    assign monitor_valid     = cdb_valid;
    assign monitor_order     = cdb_data.order;
    assign monitor_inst      = cdb_data.inst;
    assign monitor_rs1_addr  = cdb_data.rs1_addr;
    assign monitor_rs2_addr  = cdb_data.rs2_addr;
    assign monitor_rs1_rdata = cdb_data.rs1_rdata;
    assign monitor_rs2_rdata = cdb_data.rs2_rdata;
    assign monitor_rd_addr   = cdb_data.rd;
    assign monitor_rd_wdata  = cdb_data.data;
    assign monitor_pc_rdata  = cdb_data.pc;
    assign monitor_pc_wdata  = cdb_data.pc_wdata;
    assign monitor_mem_addr  = cdb_data.mem_addr;
    assign monitor_mem_rmask = cdb_data.mem_rmask;
    assign monitor_mem_wmask = cdb_data.mem_wmask;
    assign monitor_mem_rdata = cdb_data.mem_rdata;
    assign monitor_mem_wdata = cdb_data.mem_wdata;

endmodule : cpu
