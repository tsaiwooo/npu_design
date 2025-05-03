//-------------------------------------------------------------
// ADD.v
// 此模組實現 TFLM 中量化加法運算，並利用硬體加速
//-------------------------------------------------------------

`timescale 1ns / 1ps
`include "params.vh"

module ADD #
(
    parameter MAX_VECTOR_SIZE = 8
)
(
    input clk,
    input rst,
    input valid_in,
    
    // 一次8筆資料
    input wire [INT8_SIZE * MAX_VECTOR_SIZE - 1:0] input1,
    input wire [INT8_SIZE * MAX_VECTOR_SIZE - 1:0] input2,

    // quantized signals
    input wire signed [INT32_SIZE-1:0] input1_offset,
    input wire signed [INT32_SIZE-1:0] input2_offset,
    input wire        [INT32_SIZE-1:0] left_shift, 

    // input scale factor signals
    input wire signed [INT32_SIZE-1:0] input1_multiplier,
    input wire signed [INT32_SIZE-1:0] input2_multiplier,
    input wire signed [INT32_SIZE-1:0] input1_shift,
    input wire signed [INT32_SIZE-1:0] input2_shift,

    // output scale factor signals
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
    // 利用 generate 拆解向量成單一元素
    wire signed [INT8_SIZE-1:0] in1_array [0:MAX_VECTOR_SIZE-1];
    wire signed [INT8_SIZE-1:0] in2_array [0:MAX_VECTOR_SIZE-1];
    
    genvar i;
    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : input_slice
            // 使用 [高位 -: 寬度] 的語法取得每一筆 8-bit 資料
            assign in1_array[i] = input1[(i+1)*INT8_SIZE-1 -: INT8_SIZE];
            assign in2_array[i] = input2[(i+1)*INT8_SIZE-1 -: INT8_SIZE];
        end
    endgenerate

    // 針對每一筆資料實例化一個 ADD_element 模組
    wire signed [INT8_SIZE-1:0] out_array [0:MAX_VECTOR_SIZE-1];
    wire                        valid_array [0:MAX_VECTOR_SIZE-1];

    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : add_elements
            ADD_element_pipeline add_inst (
                .clk(clk),
                .rst(rst),
                .in1(in1_array[i]),
                .in2(in2_array[i]),
                .input_valid(valid_in),
                .input1_offset(input1_offset),
                .input2_offset(input2_offset),
                .left_shift(left_shift),
                .input1_multiplier(input1_multiplier),
                .input2_multiplier(input2_multiplier),
                .input1_shift(input1_shift),
                .input2_shift(input2_shift),
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

    // 將所有 element 的輸出合併到 data_o
    generate
        for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : output_assign
            assign data_o[(i+1)*INT8_SIZE-1 -: INT8_SIZE] = out_array[i];
        end
    endgenerate

    // 假設各 element 的 valid 都同步，採 AND reduction 當作全局有效訊號
    assign valid_o = valid_array[0];
endmodule