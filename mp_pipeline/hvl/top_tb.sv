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

    initial begin
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------------------------------------------
    // Main monitoring logic
    // -------------------------------------------------------------
    bit halt_seen = 0;

    always @(posedge clk) begin
        // Detect HALT only once (rising edge)
        if (mon_itf.halt && !halt_seen) begin
            halt_seen = 1;
            $display("Halt detected, ending simulation");
            #1 $finish;    // Graceful exit, allow final blocks to run
        end

        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $finish;
        end

        if (mon_itf.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end

        if (mem_itf_i.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end

        if (mem_itf_d.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end

        timeout <= timeout - 1;
    end

    final begin
        // Auto save coverage at simulation end
        $system("echo 'Saving coverage...'");
        // The vsim -do command handles actual saving
    end

endmodule
