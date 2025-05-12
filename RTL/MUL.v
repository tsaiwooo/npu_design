//-------------------------------------------------------------
// MUL.v
// 此模組實現 TFLM 中量化乘法運算，並利用硬體加速
//-------------------------------------------------------------

`timescale 1ns / 1ps
`include "params.vh"

module MUL #
(
    parameter MAX_VECTOR_SIZE = 8
)
(
    input clk,
    input rst,
    input valid_in,
    
    input wire [INT8_SIZE * MAX_VECTOR_SIZE - 1:0] input1,
    input wire [INT8_SIZE * MAX_VECTOR_SIZE - 1:0] input2,

    // quantized signals
    input wire signed [INT32_SIZE-1:0] input1_offset,
    input wire signed [INT32_SIZE-1:0] input2_offset,

    // output quantized signals
    input wire signed [INT32_SIZE-1:0] output_multiplier,
    input wire signed [INT32_SIZE-1:0] output_shift,
    input wire signed [INT32_SIZE-1:0] output_offset,

    // activation function clamping signals
    input  wire signed [31:0] quantized_activation_min,
    input  wire signed [31:0] quantized_activation_max,

    // output signals
    output wire [INT8_SIZE * MAX_VECTOR_SIZE - 1:0] data_o,
    output wire valid_o
);
    
    wire signed [INT8_SIZE-1:0] in1_array [0:MAX_VECTOR_SIZE-1];
    wire signed [INT8_SIZE-1:0] in2_array [0:MAX_VECTOR_SIZE-1];
    
    genvar i;
    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : input_slice
            assign in1_array[i] = input1[(i+1)*INT8_SIZE-1 -: INT8_SIZE];
            assign in2_array[i] = input2[(i+1)*INT8_SIZE-1 -: INT8_SIZE];
        end
    endgenerate

    wire signed [INT8_SIZE-1:0] out_array [0:MAX_VECTOR_SIZE-1];
    wire                        valid_array [0:MAX_VECTOR_SIZE-1];

    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : mul_elements
            MUL_Element mul_inst(
                .clk(clk),
                .rst(rst),
                .input_valid(valid_in),
                .in1(in1_array[i]),
                .in2(in2_array[i]),
                .input1_offset(input1_offset),
                .input2_offset(input2_offset),
                .output_multiplier(output_multiplier),
                .output_shift(output_shift),
                .output_offset(output_offset),
                .quantized_activation_min(quantized_activation_min),
                .quantized_activation_max(quantized_activation_max),
                .out(out_array[i]),
                .valid(valid_array[i])
            );
        end
    endgenerate
    // combine all the output elements to data_o
    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : output_assign
            assign data_o[(i+1)*INT8_SIZE-1 -: INT8_SIZE] = out_array[i];
        end
    endgenerate

    assign valid_o = valid_array[0] ;

endmodule