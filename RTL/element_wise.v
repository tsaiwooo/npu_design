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
    input [MAX_VECTOR_SIZE * INT8_WIDTH-1:0]                      data_in,
    input [2:0]                                 groups,
    input                                       valid_in,
    input [INT32_WIDTH-1:0]                     input_range_radius,
    input signed [INT32_WIDTH-1:0]                     input_zero_point,
    input signed [INT32_WIDTH-1:0]                     input_left_shift,
    input signed [INT32_WIDTH-1:0]                     input_multiplier,

    // -------------------------------------
    // data_out
    // -------------------------------------
    output [MAX_VECTOR_SIZE * INT8_WIDTH-1:0] data_out,
    output                 valid_out,

    output [17:0] idx1_out
);
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    wire signed [INT32_WIDTH-1:0] dequant_data_in[0:MAX_VECTOR_SIZE-1]; 
    wire vec_deq_input_valid[0:MAX_VECTOR_SIZE-1];
    wire vec_output_valid[0:MAX_VECTOR_SIZE-1];
    wire vec_deq_output_valid[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] exp_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] dequant_data_out[0:MAX_VECTOR_SIZE-1];
    reg [17:0] ele_idx;
genvar dequant_idx;
generate
    for(dequant_idx = 0; dequant_idx < MAX_VECTOR_SIZE; dequant_idx = dequant_idx + 1) begin : dequant_generate
        assign dequant_data_in[dequant_idx] = 
            (dequant_idx < groups) ?
                dequant_saturate(data_in[dequant_idx*INT8_WIDTH +: INT8_WIDTH], input_zero_point, input_range_radius)
                : 0;  // 或者指定其他的default值
        assign vec_deq_input_valid[dequant_idx] = (dequant_idx < groups) ? valid_in : 0;

        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
            .clk(clk),
            .rst(rst),
            .x(dequant_data_in[dequant_idx]),
            .quantized_multiplier(input_multiplier),
            .shift(input_left_shift),
            .input_valid(vec_deq_input_valid[dequant_idx]),
            .output_valid(vec_deq_output_valid[dequant_idx]),
            .x_mul_by_quantized_multiplier(dequant_data_out[dequant_idx])
        );
    end
endgenerate

    // exp
genvar exp_idx;
generate
    for(exp_idx = 0; exp_idx < MAX_VECTOR_SIZE; exp_idx = exp_idx + 1) begin : exp_vector
        exp_pipeline exp_pipeline_inst (
            .clk(clk),
            .rst(rst),
            .x(dequant_data_out[exp_idx]),
            .integer_bits(4'd4),
            .input_valid(vec_deq_output_valid[exp_idx]),
            .exp_x(exp_data_out[exp_idx]),
            .output_valid(vec_output_valid[exp_idx])
        );
    end
endgenerate
    // 超過input_range_radius的範圍 output直接給大小值, 這部份需要改
    // send data out(因為exp完的data是32bits, 所以都給每個data的前8個bits, 去testbench做檢查)
    assign data_out = {exp_data_out[7][7:0], exp_data_out[6][7:0], exp_data_out[5][7:0], exp_data_out[4][7:0], exp_data_out[3][7:0], exp_data_out[2][7:0], exp_data_out[1][7:0], exp_data_out[0][7:0]};
    assign valid_out = vec_output_valid[0];
    assign idx1_out = ele_idx;

    always @(posedge clk)begin
        if(!rst)begin
            ele_idx <= 0;
        end else if(valid_out)begin
            // $display("%0t: Output valid. ele_idx=%0d, data_out=%h", $time, ele_idx, data_out);
            ele_idx <= ele_idx + 1;
        end
    end

endmodule  // element_wise

