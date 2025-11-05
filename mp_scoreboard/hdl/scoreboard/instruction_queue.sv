/**
 * ============================================================================
 * 指令队列模块 (Instruction Queue)
 * ============================================================================
 * 功能：
 * - 在 Fetch 阶段和 Issue 阶段之间缓冲指令
 * - 解耦取指和发射，允许取指继续进行即使某些指令无法立即发射
 * - 提供 FIFO 队列语义 (先进先出)
 * - 支持 flush 操作 (用于分支预测错误时清空流水线)
 *
 * 接口：
 * - enq: 入队控制信号 (来自 Fetch)
 * - deq: 出队控制信号 (来自 Scoreboard Issue 逻辑)
 * - full/empty: 队列状态信号
 * - flush: 清空队列 (分支预测错误)
 * ============================================================================
 */

module instruction_queue
    import rv32i_types::*;
    #(
        parameter int DEPTH = IQ_DEPTH  // 队列深度，默认 8
    )
    (
        input  logic        clk,        // 时钟信号
        input  logic        rst,        // 复位信号 (同步复位)

        // ====================================================================
        // Enqueue 接口 (来自 Fetch 阶段)
        // ====================================================================
        input  logic        enq,        // 入队使能信号 (Fetch 有新指令)
        input  iq_entry_t   enq_data,   // 待入队的指令数据
        output logic        full,       // 队列已满标志 (反压 Fetch)

        // ====================================================================
        // Dequeue 接口 (到 Issue 阶段)
        // ====================================================================
        input  logic        deq,        // 出队使能信号 (Issue 读取指令)
        output iq_entry_t   deq_data,   // 队首指令数据
        output logic        empty,      // 队列为空标志

        // ====================================================================
        // Flush 接口 (分支预测错误时清空队列)
        // ====================================================================
        input  logic        flush       // 清空队列信号
    );

    // ========================================================================
    // 内部信号定义
    // ========================================================================

    // 队列存储 (使用数组实现循环队列)
    iq_entry_t queue [DEPTH];

    // 队列指针
    logic [$clog2(DEPTH):0] head;       // 队首指针 (读指针)
    logic [$clog2(DEPTH):0] tail;       // 队尾指针 (写指针)
    logic [$clog2(DEPTH):0] count;      // 当前队列中的指令数量

    // ========================================================================
    // 队列状态输出
    // ========================================================================
    assign full  = (count == DEPTH);    // 队列满：计数等于深度
    assign empty = (count == 0);        // 队列空：计数为 0

    // 队首数据输出 (始终输出队首元素，即使队列为空)
    assign deq_data = queue[head[$clog2(DEPTH)-1:0]];

    // ========================================================================
    // 队列控制逻辑 (同步时序逻辑)
    // ========================================================================
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            // ----------------------------------------------------------------
            // 复位或 Flush：清空队列
            // ----------------------------------------------------------------
            head  <= '0;
            tail  <= '0;
            count <= '0;

            // 清空所有队列条目 (可选，用于仿真调试)
            for (int i = 0; i < DEPTH; i++) begin
                queue[i] <= '0;
            end

        end else begin
            // ----------------------------------------------------------------
            // 正常操作：处理入队和出队
            // ----------------------------------------------------------------

            // === 情况 1: 仅入队 ===
            if (enq && !full && !(deq && !empty)) begin
                queue[tail[$clog2(DEPTH)-1:0]] <= enq_data;  // 写入队尾
                tail <= (tail + 1) % DEPTH;                  // 移动队尾指针
                count <= count + 1;                          // 增加计数

            // === 情况 2: 仅出队 ===
            end else if (deq && !empty && !(enq && !full)) begin
                head <= (head + 1) % DEPTH;                  // 移动队首指针
                count <= count - 1;                          // 减少计数

            // === 情况 3: 同时入队和出队 ===
            end else if (enq && !full && deq && !empty) begin
                queue[tail[$clog2(DEPTH)-1:0]] <= enq_data;  // 写入队尾
                tail <= (tail + 1) % DEPTH;                  // 移动队尾指针
                head <= (head + 1) % DEPTH;                  // 移动队首指针
                // count 不变 (一进一出)
            end
        end
    end

    // ========================================================================
    // 断言 (Assertion) - 用于仿真验证
    // ========================================================================
    `ifndef SYNTHESIS
        // 检查：不应该在队列满时入队
        always @(posedge clk) begin
            if (!rst && !flush && enq && full) begin
                $error("[IQ] Attempt to enqueue when queue is FULL!");
            end
        end

        // 检查：不应该在队列空时出队
        always @(posedge clk) begin
            if (!rst && !flush && deq && empty) begin
                $error("[IQ] Attempt to dequeue when queue is EMPTY!");
            end
        end

        // 检查：队列计数不应该超过深度
        always @(posedge clk) begin
            if (!rst && count > DEPTH) begin
                $error("[IQ] Queue count exceeds DEPTH!");
            end
        end
    `endif

endmodule : instruction_queue
