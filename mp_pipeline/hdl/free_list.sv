module free_list #(
    parameter PHYS_REGS = 64
)(
    input  logic       clk,
    input  logic       rst,

    // allocate a physical register
    output logic [5:0] alloc_phys,
    output logic       alloc_valid,

    // free one physical register when WB commits
    input  logic       free_en,
    input  logic [5:0] free_phys
);

    // ================================
    //   FIFO queue of free registers
    // ================================
    logic [5:0] queue [PHYS_REGS-1:0];
    logic [6:0] head;   // dequeue pointer
    logic [6:0] tail;   // enqueue pointer
    logic [6:0] count;  // number of free regs

    // ================================
    // Reset → initialize free list
    // ================================
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            // Fill free list with all physical regs 1–63 (0 reserved for x0)
            for (i = 1; i < PHYS_REGS; i++) begin
                queue[i-1] <= i[5:0];
            end
            head  <= 0;
            tail  <= PHYS_REGS-1;
            count <= PHYS_REGS-1;   // phys 0 is never free
        end
        else begin
            // ========================
            // Allocation (dequeue)
            // ========================
            if (alloc_valid) begin
                head <= head + 1;
                count <= count - 1;
            end

            // ========================
            // Free (enqueue)
            // ========================
            if (free_en) begin
                queue[tail] <= free_phys;
                tail <= tail + 1;
                count <= count + 1;
            end
        end
    end

    // ================================
    // Output: allocate physical reg
    // ================================
    assign alloc_valid = (count > 0);
    assign alloc_phys  = queue[head];

endmodule
