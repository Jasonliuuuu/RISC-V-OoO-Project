module free_list (
    input logic clk,
    input logic rst,

    // Allocation (dequeue)
    input  logic alloc_en,
    output logic alloc_valid,
    output logic [5:0] alloc_phys,

    // Normal free (enqueue) - from commit
    input logic       free_en,
    input logic [5:0] free_phys,
    
    // Flush recovery - return multiple physical registers (up to 16)
    input logic [4:0] flush_free_count,
    input logic [5:0] flush_free_phys [15:0]
);

    // ================================
    //   FIFO queue of free registers
    // ================================
    logic [5:0] queue [64-1:0];
    logic [6:0] head;   // dequeue pointer
    logic [6:0] tail;   // enqueue pointer
    logic [6:0] count;  // number of free regs

    // ================================
    // initial: all phys 1-63 are free
    // ================================
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            head  <= 7'd0;
            tail  <= 7'd63;  // 63 registers
            count <= 7'd63;
            for (int i = 1; i < 64; i++) begin
                queue[i-1] <= i[5:0];
            end
        end
        else begin
            // ========================
            // Allocation and Free can happen in SAME CYCLE!
            // Need to handle atomically to avoid count corruption
            // PLUS: Flush recovery can return 0-3 additional registers
            // ========================
            
            logic [2:0] total_frees;
            logic [2:0] net_change;
            
            // Calculate total frees: normal free + flush recoveries
            total_frees = (free_en ? 3'd1 : 3'd0) + flush_free_count;
            
            // Net change: frees - allocs
            if (alloc_valid && !total_frees) begin
                // Only allocation
                head <= head + 1;
                count <= count - 1;
                $display("[FREE_LIST] Dequeue: allocated phys=%0d, count: %0d->%0d", 
                         queue[head], count, count - 1);
            end
            else if (!alloc_valid && total_frees) begin
                // Only frees (normal + flush recovery)
                // Enqueue normal free
                if (free_en) begin
                    queue[tail] <= free_phys;
                    tail <= tail + 1;
                end
                // Enqueue flush recoveries
                for (int i = 0; i < flush_free_count; i++) begin
                    queue[tail + (free_en ? 1 : 0) + i] <= flush_free_phys[i];
                end
                tail <= tail + total_frees;
                count <= count + total_frees;
                $display("[FREE_LIST] Enqueue: normal=%0d flush=%0d, count: %0d->%0d", 
                         free_en, flush_free_count, count, count + total_frees);
            end
            else if (alloc_valid && total_frees) begin
                // Both allocation and frees - net effect
                net_change = total_frees - 3'd1;
                // Enqueue all frees
                if (free_en) begin
                    queue[tail] <= free_phys;
                end
                for (int i = 0; i < flush_free_count; i++) begin
                    queue[tail + (free_en ? 1 : 0) + i] <= flush_free_phys[i];
                end
                // Update pointers
                head <= head + 1;
                tail <= tail + total_frees;
                count <= count + net_change;
                $display("[FREE_LIST] Simultaneous: alloc phys=%0d, frees normal=%0d flush=%0d, count: %0d->%0d",
                         queue[head], free_en, flush_free_count, count, count + net_change);
            end
        end
    end

    // ================================
    // Output: allocate physical reg
    // ================================
    assign alloc_valid = (count > 0);
    // Output the physical register from queue head
    // DO NOT provide a "safe default" of 0 - that would cause phys_reg 0
    // to be allocated to non-x0 architectural registers!
    // If alloc_valid=0, alloc_phys will be indeterminate, but rename_unit
    // should check alloc_valid before using alloc_phys.
    assign alloc_phys  = queue[head];

endmodule
