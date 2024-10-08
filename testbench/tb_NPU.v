`timescale 1ns / 1ps

module tb_NPU;

// NPU Parameters
parameter PERIOD     = 10;
parameter BANDWIDTH  = 32;

// NPU Inputs
reg   clk                                  = 0 ;
reg   rst                                  = 0 ;
reg   [BANDWIDTH-1:0]  in_data             = 0 ;
reg   [31:0]           weight              = 0 ;
reg   valid                                = 0 ;

// NPU Outputs
wire  [31:0]           out_data            ;
wire                   done                ;

// Clock generation
initial begin
    forever #(PERIOD/2)  clk = ~clk;
end

// Reset logic
initial begin
    rst = 1;
    #(PERIOD*2) rst = 0;
end

// Instantiate the NPU module
NPU #(
    .BANDWIDTH ( BANDWIDTH )
) u_NPU (
    .clk       ( clk       ),
    .rst       ( rst       ),
    .in_data   ( in_data   ),
    .weight    ( weight    ),
    .valid     ( valid     ),
    .out_data  ( out_data  ),
    .done      ( done      )
);

// Verdi waveform dump
initial begin
    // FSDB file name
    $fsdbDumpfile("verdi.fsdb");
    
    // Dump all variables in the design hierarchy (from tb_NPU)
    $fsdbDumpvars(0, tb_NPU,"+all");
end

initial begin
    // Apply reset
    rst = 1;
    #(PERIOD*2);
    rst = 0;

    // Wait for reset deassertion
    #(PERIOD*2);

    // Start providing data and weights every cycle
    valid = 1;

    // Test Cases - Providing data and weight every clock cycle
    in_data = 32'h00000001;  weight = 32'h00000002; #(PERIOD);
    in_data = 32'h00000003;  weight = 32'h00000004; #(PERIOD);
    in_data = 32'h00000005;  weight = 32'h00000006; #(PERIOD);
    in_data = 32'h00000007;  weight = 32'h00000008; #(PERIOD);
    in_data = 32'h00000009;  weight = 32'h0000000A; #(PERIOD);
    in_data = 32'h0000000B;  weight = 32'h0000000C; #(PERIOD);
    in_data = 32'h0000000D;  weight = 32'h0000000E; #(PERIOD);
    in_data = 32'h0000000F;  weight = 32'h00000010; #(PERIOD);

    // Wait for completion of last operation
    wait (done == 1);
    $display("All Test Cases complete. Final Output data: %h", out_data);

    // Finish simulation
    #(PERIOD);
    $finish;
end

endmodule
