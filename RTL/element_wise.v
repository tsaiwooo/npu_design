`timescale 1ns / 1ps
`include "params.vh"
`include "function.vh"

module element_wise #
(
    parameter INT32_WIDTH = 32,
    parameter INT8_WIDTH = 8,
    parameter DEQUANT_WIDTH = 32,
    parameter ADDR_WIDTH = 13,
    parameter MAX_VECTOR_SIZE = 8,
    parameter MAX_ITER = 8
)
(
    input                  clk,
    input                  rst,
    // -------------------------------------
    // exp_data_in, 之後看哪個element-wise的function要啟用就增加port
    // -------------------------------------
    input signed [INT8_WIDTH-1:0]                      data_in,
    input                                       valid_in,
    input [INT32_WIDTH-1:0]                     input_range_radius,
    input signed [INT32_WIDTH-1:0]                     input_zero_point,
    input signed [INT32_WIDTH-1:0]                     input_left_shift,
    input signed [INT32_WIDTH-1:0]                     input_multiplier,

    // -------------------------------------
    // data_out
    // -------------------------------------
    output [INT8_WIDTH-1:0] data_out,
    output                 valid_out,

    output [17:0] data_idx_o
);
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    wire signed [INT32_WIDTH-1:0] dequant_data_in; 
    wire exp_output_valid;
    wire deq_output_valid;
    wire signed [INT32_WIDTH-1:0] exp_data_out;
    wire signed [INT32_WIDTH-1:0] dequant_data_out;
    reg [17:0] ele_idx;

    assign dequant_data_in = dequant_saturate(data_in, input_zero_point, input_range_radius);

    MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
        .clk(clk),
        .rst(rst),
        .x(dequant_data_in),
        .quantized_multiplier(input_multiplier),
        .shift(input_left_shift),
        .input_valid(valid_in),
        .output_valid(deq_output_valid),
        .x_mul_by_quantized_multiplier(dequant_data_out)
    );

    // exp
    exp_pipeline exp_pipeline_inst (
        .clk(clk),
        .rst(rst),
        .x(dequant_data_out),
        .integer_bits(4'd4),
        .input_valid(deq_output_valid),
        .exp_x(exp_data_out),
        .output_valid(exp_output_valid)
    );

    // 超過input_range_radius的範圍 output直接給大小值, 這部份需要改
    // send data out(因為exp完的data是32bits, 所以都給每個data的前8個bits, 去testbench做檢查)
    assign data_out = exp_data_out[7:0];
    assign valid_out = exp_output_valid;
    assign data_idx_o = ele_idx;

    always @(posedge clk)begin
        if(!rst)begin
            ele_idx <= 0;
        end else if(valid_out)begin
            $display("%0t: Output valid. ele_idx=%0d, data_out=%h", $time, ele_idx, exp_data_out);
            ele_idx <= ele_idx + 1'b1;
        end
    end

endmodule  // element_wise

