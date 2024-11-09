`timescale 1ns / 1ps
`include "params.vh"

module GEMM #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8
)
(
    input  wire                   clk,
    input  wire                   rst,
    // convolution signals
    // convolution en
    input  wire                   convolution_en,
    // convolution input metadata
    input  wire [ADDR_WIDTH-1:0]  img_row,
    input  wire [ADDR_WIDTH-1:0]  img_col,
    input  wire [ADDR_WIDTH-1:0]  ker_row,
    input  wire [ADDR_WIDTH-1:0]  ker_col,
    // convolution img and kernel data
    input  wire [SRAM_WIDTH_O-1:0]  data_in,
    input  wire [SRAM_WIDTH_O-1:0]  weight_in,
    // convolution output signal control
    output wire                   mac_valid_out,
    output wire signed [2*DATA_WIDTH-1:0] mac_out,
    // convolution output image metadata
    output wire [ADDR_WIDTH-1:0]  conv_row,
    output wire [ADDR_WIDTH-1:0]  conv_col,
    output wire [ADDR_WIDTH-1:0]  for_conv_row,
    output wire [ADDR_WIDTH-1:0]  for_conv_col,
    // convolution output weight idx metadata
    output [ADDR_WIDTH-1:0]  weight_idx_o,
    output wire [ADDR_WIDTH-1:0]  idx1_out
);
    
    convolution #
    (
        .MAX_MACS(MAX_MACS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    )
    (
        .clk(clk),
        .rst(rst),
        .en(convolution_en),
        // input metadata
        .img_row(img_row),
        .img_col(img_col),
        .ker_row(ker_row),
        .ker_col(ker_col),
        // img and kernel data
        .data_in(data_in),
        .weight_in(weight_in),
        // output signal control
        .mac_valid_out(mac_valid_out),
        .mac_out(mac_out),
        // output metadata
        .conv_row(conv_row),
        .conv_col(conv_col),
        .for_conv_row(for_conv_row),
        .for_conv_col(for_conv_col),
        .weight_idx_o(weight_idx_o),
        .idx1_out(idx1_out)
    );


endmodule