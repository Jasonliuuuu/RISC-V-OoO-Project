/**
 * ============================================================================
 * Common Data Bus (CDB) 仲裁器
 * ============================================================================
 * 功能：
 * - 管理多个功能单元完成时的 CDB 访问冲突
 * - 当多个 FU 同时完成时，选择一个广播到 CDB
 * - 使用优先级仲裁或轮询仲裁
 * - 广播结果到所有等待的 FU 和 Scoreboard
 *
 * 仲裁策略：
 * - 固定优先级：ALU > MUL > DIV > Load/Store > Branch
 * - 可改为轮询 (Round-Robin) 以提高公平性
 *
 * 输出：
 * - cdb_data: 广播的数据
 * - cdb_valid: CDB 上有有效数据
 * - cdb_grant[]: 给每个 FU 的授权信号
 * ============================================================================
 */

module common_data_bus
    import rv32i_types::*;
    #(
        parameter int NUM_FU = TOTAL_FU
    )
    (
        input  logic        clk,
        input  logic        rst,

        // ====================================================================
        // 来自所有 FU 的完成请求
        // ====================================================================
        input  cdb_entry_t  fu_complete [NUM_FU],      // 每个 FU 的完成数据
        input  logic        fu_complete_valid [NUM_FU], // 每个 FU 的完成有效信号

        // ====================================================================
        // CDB 输出 (广播到 Scoreboard 和所有 FU)
        // ====================================================================
        output cdb_entry_t  cdb_data,       // CDB 上的数据
        output logic        cdb_valid,      // CDB 有效信号

        // ====================================================================
        // 反馈给 FU 的授权信号
        // ====================================================================
        output logic        cdb_grant [NUM_FU]  // 哪个 FU 获得了 CDB 访问权
    );

    // ========================================================================
    // 仲裁策略选择
    // ========================================================================
    // 0: 固定优先级 (Fixed Priority)
    // 1: 轮询 (Round-Robin)
    localparam ARBITER_TYPE = 0;

    // ========================================================================
    // 轮询仲裁状态 (如果使用)
    // ========================================================================
    logic [$clog2(NUM_FU)-1:0] rr_pointer;  // 轮询指针

    // ========================================================================
    // 固定优先级仲裁逻辑 (组合逻辑)
    // ========================================================================
    generate
        if (ARBITER_TYPE == 0) begin : gen_fixed_priority
            // ================================================================
            // 固定优先级仲裁
            // 优先级：FU[0] > FU[1] > ... > FU[NUM_FU-1]
            // 即：ALU > ALU > MUL > DIV > Load/Store > Branch
            // ================================================================
            always_comb begin
                cdb_valid = 1'b0;
                cdb_data = '0;

                for (int i = 0; i < NUM_FU; i++) begin
                    cdb_grant[i] = 1'b0;
                end

                // 从最高优先级开始遍历，找到第一个有效的完成请求
                for (int i = 0; i < NUM_FU; i++) begin
                    if (fu_complete_valid[i]) begin
                        cdb_valid = 1'b1;
                        cdb_data = fu_complete[i];
                        cdb_grant[i] = 1'b1;
                        break;  // 找到后停止 (最高优先级)
                    end
                end
            end

        end else begin : gen_round_robin
            // ================================================================
            // 轮询仲裁 (Round-Robin)
            // 公平地分配 CDB 访问权，避免某些 FU 饥饿
            // ================================================================

            // 更新轮询指针
            always_ff @(posedge clk) begin
                if (rst) begin
                    rr_pointer <= '0;
                end else if (cdb_valid) begin
                    // 移动到下一个 FU
                    rr_pointer <= (rr_pointer + 1) % NUM_FU;
                end
            end

            // 仲裁逻辑
            always_comb begin
                cdb_valid = 1'b0;
                cdb_data = '0;

                for (int i = 0; i < NUM_FU; i++) begin
                    cdb_grant[i] = 1'b0;
                end

                // 从当前轮询指针开始，循环查找有效请求
                for (int offset = 0; offset < NUM_FU; offset++) begin
                    automatic int idx;
                    idx = (rr_pointer + offset) % NUM_FU;

                    if (fu_complete_valid[idx]) begin
                        cdb_valid = 1'b1;
                        cdb_data = fu_complete[idx];
                        cdb_grant[idx] = 1'b1;
                        break;  // 找到后停止
                    end
                end
            end
        end
    endgenerate

    // ========================================================================
    // 冲突检测 (用于调试)
    // ========================================================================
    `ifndef SYNTHESIS
        integer conflict_count;

        always_comb begin
            conflict_count = 0;
            for (int i = 0; i < NUM_FU; i++) begin
                if (fu_complete_valid[i]) begin
                    conflict_count++;
                end
            end
        end

        // 当多个 FU 同时完成时输出警告
        always @(posedge clk) begin
            if (!rst && conflict_count > 1) begin
                $display("[CDB] Warning: %0d FUs completed simultaneously at time %0t",
                         conflict_count, $time);
            end
        end
    `endif

    // ========================================================================
    // CDB 利用率统计 (用于性能分析)
    // ========================================================================
    `ifndef SYNTHESIS
        longint cdb_busy_cycles;
        longint total_cycles;

        always_ff @(posedge clk) begin
            if (rst) begin
                cdb_busy_cycles <= 0;
                total_cycles <= 0;
            end else begin
                total_cycles <= total_cycles + 1;
                if (cdb_valid) begin
                    cdb_busy_cycles <= cdb_busy_cycles + 1;
                end
            end
        end

        // 在仿真结束时输出 CDB 利用率
        final begin
            if (total_cycles > 0) begin
                automatic real utilization;
                utilization = (real'(cdb_busy_cycles) / real'(total_cycles)) * 100.0;
                $display("===========================================");
                $display("CDB Utilization Statistics:");
                $display("  Total Cycles: %0d", total_cycles);
                $display("  CDB Busy Cycles: %0d", cdb_busy_cycles);
                $display("  Utilization: %.2f%%", utilization);
                $display("===========================================");
            end
        end
    `endif

endmodule : common_data_bus
