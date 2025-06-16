// ----------------------------
// Description: data write address -> word address, use 1 MSB to select which bank
//              data read address  -> bits address, should shift by 3 and use 1 MSB to select which bank
// ----------------------------
// support unaligned access
`timescale 1ns / 1ps
`include "params.vh"
`include "function.vh"

module sram_64bits
#(parameter DATA_WIDTH = 32, N_ENTRIES = 1024, parameter DATA_WIDTH_O = 64)
(
    input                           clk_i,
    input                           en_i,
    input                           we_i,
    input  [MAX_ADDR_WIDTH-1: 0] addr_i,
    input  [SRAM_WIDTH_O-1: 0]        data_i,
    output reg [SRAM_WIDTH_O-1: 0]    data_o
);

    (* ram_style = "block" *) reg [SRAM_WIDTH_O-1 : 0] RAM [N_ENTRIES>>1-1: 0];
    (* ram_style = "block" *) reg [SRAM_WIDTH_O-1 : 0] RAM1 [N_ENTRIES>>1-1: 0];
    wire [MAX_ADDR_WIDTH-1: 0] word_addr;
    assign word_addr = addr_i >> 3;

    wire [SRAM_WIDTH_O-1:0] d_even = (word_addr[0] == 1'b0)? RAM [word_addr>>1]: RAM[word_addr>>1+1];
    wire [SRAM_WIDTH_O-1:0] d_odd  = RAM1[word_addr>>1];

    always@(posedge clk_i) begin
        if (en_i) begin
            // write operation
            if(we_i) begin
                if(addr_i[0] == 1'b0)
                    RAM[addr_i>>1] <= data_i;
                else
                    RAM1[addr_i>>1] <= data_i;
            // read operaition
            end else begin
                // data_o <= RAM[addr_i];
                // data_o <= get_specific_64bits({RAM[word_addr+1],RAM[word_addr]},addr_i);
                data_o <= (word_addr[0] == 1'b0)? get_specific_64bits({d_odd,d_even},addr_i) :
                                               get_specific_64bits({d_even,d_odd},addr_i) ;
            end
        end
    end


endmodule