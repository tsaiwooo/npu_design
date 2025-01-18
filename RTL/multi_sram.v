`include "params.vh"
`timescale 1ns / 1ps

module multi_sram #
(
    parameter ADDR_WIDTH = 13,
    parameter INT8_WIDTH = 8
)
(
    input wire clk,
    input wire rst,
    input wire [7:0] en,
    input wire [7:0] we,
    input wire [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr,  
    input wire [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_in,
    output wire [NUM_SRAMS * SRAM_WIDTH_O - 1 : 0] data_out
);


    // Intermediate wires to connect each SRAM's inputs and outputs
    wire signed [INT8_WIDTH-1:0] sram_data_in[0:NUM_SRAMS-1];
    wire [SRAM_WIDTH_O-1:0] sram_data_out[0:NUM_SRAMS-1];
`ifndef synthesis
    wire [MAX_ADDR_WIDTH-1:0] sram_addr[0:NUM_SRAMS-1];
`else
    wire [6:0] sram_addr[0:NUM_SRAMS-1];
`endif

    genvar i;
    generate
        for (i = 0; i < NUM_SRAMS; i = i + 1) begin : assign_gen
            assign sram_data_in[i] = data_in[i * MAX_DATA_WIDTH +: DATA_WIDTHS[i]];
            assign data_out[i * SRAM_WIDTH_O +: SRAM_WIDTH_O] = sram_data_out[i];
            assign sram_addr[i] = addr[i * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH];
        end
    endgenerate    
    // Generate SRAM instances
    generate
        for (i = 0; i < NUM_SRAMS; i = i + 1) begin : sram_gen
            sram #(
                .DATA_WIDTH(DATA_WIDTHS[i]),
                .N_ENTRIES(N_ENTRIES[i])
            ) sram_inst (
                .clk_i(clk),
                .en_i(en[i]),
                .we_i(we[i]),
                .addr_i(sram_addr[i]),
                .data_i(sram_data_in[i]),
                .data_o(sram_data_out[i])
            );
        end
    endgenerate

endmodule
