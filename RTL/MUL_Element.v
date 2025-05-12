`timescale 1ns / 1ps
`include "params.vh"

module MUL_Element (
    input clk,
    input rst,
    input input_valid,
    input signed [INT8_SIZE-1:0] in1,
    input signed [INT8_SIZE-1:0] in2,
    input signed [INT32_SIZE-1:0] input1_offset,
    input signed [INT32_SIZE-1:0] input2_offset,
    input signed [INT32_SIZE-1:0] output_multiplier,
    input signed [INT32_SIZE-1:0] output_shift,
    input signed [INT32_SIZE-1:0] output_offset,
    input signed [31:0] quantized_activation_min,
    input signed [31:0] quantized_activation_max,
    output wire signed [INT8_SIZE-1:0] out,
    output wire valid
);

    //===================================================
    // Stage 0: 鎖存所有參數 (每個參數一個 always)
    //===================================================
    reg signed [INT32_SIZE-1:0] stage0_output_multiplier;
    reg signed [INT32_SIZE-1:0] stage0_output_shift;
    reg signed [INT32_SIZE-1:0] stage0_output_offset;
    reg signed [31:0] stage0_quantized_activation_min;
    reg signed [31:0] stage0_quantized_activation_max;
    

    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_multiplier <= 0;
      else stage0_output_multiplier <= output_multiplier;

    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_shift <= 0;
      else stage0_output_shift <= output_shift;

    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_offset <= 0;
      else stage0_output_offset <= output_offset;
    
    always @(posedge clk or negedge rst)
      if (!rst) stage0_quantized_activation_min <= 0;
      else stage0_quantized_activation_min <= quantized_activation_min;

    always @(posedge clk or negedge rst)
      if (!rst) stage0_quantized_activation_max <= 0;
      else stage0_quantized_activation_max <= quantized_activation_max;

    //===================================================
    // Stage 1: 計算
    // 1. 將 in1, in2 加上offset後相乘做requant
    //===================================================
    wire signed [INT32_SIZE-1:0] requant_input;
    wire signed [INT32_SIZE-1:0] requant_output;
    assign requant_input = (in1 + input1_offset) * (in2 + input2_offset);

    MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
        .clk(clk),
        .rst(rst),
        .x(requant_input),
        .quantized_multiplier(output_multiplier),
        .shift(output_shift),
        .input_valid(input_valid),
        .output_valid(valid),
        .x_mul_by_quantized_multiplier(requant_output)
    );

    //===================================================
    // Stage 2: requant_output 加上 offset 且做clamped
    //===================================================
    wire signed [INT8_SIZE-1:0] clamped_output;
    assign clamped_output = (requant_output + stage0_output_offset) < stage0_quantized_activation_min ? stage0_quantized_activation_min : 
                            (requant_output + stage0_output_offset) > stage0_quantized_activation_max ? stage0_quantized_activation_max : (requant_output + stage0_output_offset);
    assign out = clamped_output;
    

endmodule