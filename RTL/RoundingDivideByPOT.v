// ---------------------
// function: RoundingDivideByPOT
// purpose: Perform a rounding division operation by a power of two
// ---------------------
`timescale 1ns / 1ps
`include "params.vh"

module RoundingDivideByPOT #(parameter WIDTH = 32)(
    input signed [WIDTH-1:0] x,
    input [4:0] exponent,  // exponent should be 5 bits to handle values 0-31
    output reg signed [WIDTH-1:0] result
);

    // Intermediate signals
    wire signed [WIDTH-1:0] mask;
    wire signed [WIDTH-1:0] remainder;
    wire signed [WIDTH-1:0] threshold;
    wire signed [WIDTH-1:0] shifted_x;

    assign mask = (1 << exponent) - 1;         // Create mask with bits set by exponent
    assign remainder = x & mask;               // Calculate remainder using mask
    assign threshold = (mask >> 1) + (x < 0);  // Calculate threshold based on sign of x
    assign shifted_x = x >>> exponent;         // Arithmetic right shift of x by exponent

    always @(*) begin
        // Final rounding operation: add 1 if remainder exceeds threshold
        result = shifted_x + ((remainder > threshold) || (remainder == threshold && (shifted_x & 1)));
    end

endmodule // RoundingDivideByPOT