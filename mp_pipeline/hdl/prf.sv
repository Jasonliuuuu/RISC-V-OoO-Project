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
    
    // Debug PRF reads for specific physical registers
    always_comb begin
        if (rs2_phys == 6'd26 || rs2_phys == 6'd8 || rs2_phys == 6'd30) begin
            $display("[PRF READ] rs2_phys=%0d → rs2_val=0x%h (prf_mem[%0d]=0x%h)",
                     rs2_phys, rs2_val, rs2_phys, prf_mem[rs2_phys]);
        end
    end

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
