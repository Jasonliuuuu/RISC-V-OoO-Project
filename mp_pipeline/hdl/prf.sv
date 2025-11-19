module prf #(
    parameter PHYS_REGS = 64
)(
    input  logic         clk,
    input  logic         rst,

    // read ports
    input  logic [5:0]   rs1_phys,
    input  logic [5:0]   rs2_phys,
    output logic [31:0]  rs1_val,
    output logic [31:0]  rs2_val,

    // write port
    input  logic         we,
    input  logic [5:0]   rd_phys,
    input  logic [31:0]  rd_val
);

    logic [31:0] prf_mem [PHYS_REGS-1:0];

    // read (combinational)
    assign rs1_val = prf_mem[rs1_phys];
    assign rs2_val = prf_mem[rs2_phys];

    // write (sequential)
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < PHYS_REGS; i++)
                prf_mem[i] <= 32'b0;
        end
        else if (we && rd_phys != 6'd0) begin
            prf_mem[rd_phys] <= rd_val;
        end
    end

endmodule
