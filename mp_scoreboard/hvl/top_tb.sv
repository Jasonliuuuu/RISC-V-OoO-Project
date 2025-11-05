module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps = 5;
    bit clk;
    always #(clock_half_period_ps) clk = ~clk;

    bit rst;
    int timeout = 10000000; // in cycles, change according to your needs

    mem_itf mem_itf_i(.*);
    mem_itf mem_itf_d(.*);
    // magic_dual_port mem(.itf_i(mem_itf_i), .itf_d(mem_itf_d));
    // ordinary_dual_port mem(.itf_i(mem_itf_i), .itf_d(mem_itf_d));
    random_tb mem(.itf_i(mem_itf_i), .itf_d(mem_itf_d));
    mon_itf mon_itf(.*);
    monitor monitor(.itf(mon_itf));

    cpu dut(
        .clk        (clk),
        .rst        (rst),
        .imem_addr  (mem_itf_i.addr),
        .imem_rmask (mem_itf_i.rmask),
        .imem_rdata (mem_itf_i.rdata),
        .imem_resp  (mem_itf_i.resp),
        .dmem_addr  (mem_itf_d.addr),
        .dmem_rmask (mem_itf_d.rmask),
        .dmem_wmask (mem_itf_d.wmask),
        .dmem_rdata (mem_itf_d.rdata),
        .dmem_wdata (mem_itf_d.wdata),
        .dmem_resp  (mem_itf_d.resp)
    );

    `include "../hvl/rvfi_reference.svh"
    
    // ========================================
    // 新增：指令计数器
    // ========================================
    longint instruction_count = 0;
    longint target_instructions = 60000;
    bit target_reached = 0;
    
    initial begin
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    end
    
    // ========================================
    // 新增：指令计数逻辑
    // ========================================
    always @(posedge clk) begin
        // 计数每条 commit 的指令
        if (mon_itf.valid && !rst) begin
            instruction_count++;
            
            // 每 10,000 条打印进度
            if (instruction_count % 10000 == 0) begin
                $display("Progress: %0d / %0d instructions completed", 
                         instruction_count, target_instructions);
            end
            
            // 检查是否达到目标
            if (instruction_count >= target_instructions && !target_reached) begin
                target_reached = 1;
                $display("==================================================");
                $display("SUCCESS: Completed %0d instructions!", target_instructions);
                $display("==================================================");
                repeat (5) @(posedge clk);
                $finish;
            end
        end
    end

    bit halt_seen = 0;

    always @(posedge clk) begin
        // ========================================
        // 优先级 1: 错误检查（最高优先级）
        // ========================================
        if (mon_itf.error != 0) begin
            $error("RVFI Monitor Error detected at instruction %0d", 
                   instruction_count);
            repeat (5) @(posedge clk);
            $finish;
        end
        
        if (mem_itf_i.error != 0) begin
            $error("Instruction Memory Error at instruction %0d", 
                   instruction_count);
            repeat (5) @(posedge clk);
            $finish;
        end
        
        if (mem_itf_d.error != 0) begin
            $error("Data Memory Error at instruction %0d", 
                   instruction_count);
            repeat (5) @(posedge clk);
            $finish;
        end
        
        // ========================================
        // 优先级 2: Halt 检查（仅在未达到目标时警告）
        // ========================================
        if (mon_itf.halt && !halt_seen && !target_reached) begin
            halt_seen = 1;
            
            if (instruction_count < target_instructions) begin
                $display("==================================================");
                $display("WARNING: Halt detected early at instruction %0d", 
                         instruction_count);
                $display("Expected %0d instructions", target_instructions);
                $display("==================================================");
            end else begin
                $display("Halt detected, ending simulation");
            end
            
            repeat (5) @(posedge clk);
            $finish;
        end
        
        // ========================================
        // 优先级 3: Timeout 检查
        // ========================================
        if (timeout == 0) begin
            $error("TB Error: Timed out at instruction %0d", instruction_count);
            $error("Expected %0d instructions", target_instructions);
            $finish;
        end
        
        timeout <= timeout - 1;
    end

    final begin
        // Auto save coverage at simulation end
        $system("echo 'Saving coverage...'");
        $display("Final instruction count: %0d", instruction_count);
        // The vsim -do command handles actual saving
    end

endmodule
