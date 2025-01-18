`timescale 1ns / 1ps
`include "params.vh"

module sram_64bits
#(parameter DATA_WIDTH = 32, N_ENTRIES = 1024, parameter DATA_WIDTH_O = 64)
(
    input                           clk_i,
    input                           en_i,
    input                           we_i,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i,
    input  [DATA_WIDTH-1: 0]        data_i,
    output reg [SRAM_WIDTH_O-1: 0]    data_o
);

    reg [DATA_WIDTH-1 : 0] RAM [N_ENTRIES-1: 0];
    wire [6:0] shift_amount;
    wire [6:0] nums_input;
    assign shift_amount = $clog2(DATA_WIDTH);
    assign nums_input = (SRAM_WIDTH_O >> shift_amount);

    integer i;
    always@(posedge clk_i) begin
        if (en_i) begin
            // write operation
            if(we_i) begin
                RAM[addr_i] <= data_i;
            // read operaition
            end else begin
                data_o <= RAM[addr_i];
            end
        end
    end


endmodule