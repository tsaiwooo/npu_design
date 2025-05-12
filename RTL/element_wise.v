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
    input                  init,
    // -------------------------------------
    // exp_data_in, 之後看哪個element-wise的function要啟用就增加port
    // -------------------------------------
    input [INT64_SIZE-1:0]                      data_in,
    input [3:0]                                 groups,
    input                                       valid_in,
    input [INT32_WIDTH-1:0]                            exp_deq_input_range_radius,
    input signed [INT32_WIDTH-1:0]                     exp_deq_input_zero_point,
    input signed [INT32_WIDTH-1:0]                     exp_deq_input_left_shift,
    input  [INT32_WIDTH-1:0]                     exp_deq_input_multiplier,
    input  [INT32_WIDTH-1:0]                     exp_req_input_quantized_multiplier,
    input signed [INT32_WIDTH-1:0]                     exp_req_input_shift,
    input signed [INT32_WIDTH-1:0]                     exp_req_input_offset,

    // -------------------------------------
    // Reciprocal signals
    // -------------------------------------
    input signed [INT32_WIDTH-1:0]                     reciprocal_deq_input_zero_point,
    input signed [INT32_WIDTH-1:0]                     reciprocal_deq_input_range_radius,
    input signed [INT32_WIDTH-1:0]                     reciprocal_deq_input_left_shift,
    input  [INT32_WIDTH-1:0]                     reciprocal_deq_input_multiplier,
    input  [INT32_WIDTH-1:0]                     reciprocal_req_input_quantized_multiplier,
    input signed [INT32_WIDTH-1:0]                     reciprocal_req_input_shift,
    input signed [INT32_WIDTH-1:0]                     reciprocal_req_input_offset,

    // -------------------------------------
    // ADD signals
    // -------------------------------------
    input signed [INT32_WIDTH-1:0]                     add_input1_offset,
    input signed [INT32_WIDTH-1:0]                     add_input2_offset,
    input signed [INT32_WIDTH-1:0]                     add_left_shift,
    input  [INT32_WIDTH-1:0]                     add_input1_multiplier,
    input  [INT32_WIDTH-1:0]                     add_input2_multiplier,
    input signed [INT32_WIDTH-1:0]                     add_input1_shift,
    input signed [INT32_WIDTH-1:0]                     add_input2_shift,
    input  [INT32_WIDTH-1:0]                     add_output_multiplier,
    input signed [INT32_WIDTH-1:0]                     add_output_shift,
    input signed [INT32_WIDTH-1:0]                     add_output_offset,
    input signed [31:0]                               add_quantized_activation_min,
    input signed [31:0]                               add_quantized_activation_max,

    // -------------------------------------
    // SUB signals
    // -------------------------------------
    input signed [INT32_WIDTH-1:0]                     sub_input1_offset,
    input signed [INT32_WIDTH-1:0]                     sub_input2_offset,
    input signed [INT32_WIDTH-1:0]                     sub_left_shift,
    input  [INT32_WIDTH-1:0]                     sub_input1_multiplier,
    input  [INT32_WIDTH-1:0]                     sub_input2_multiplier,
    input signed [INT32_WIDTH-1:0]                     sub_input1_shift,
    input signed [INT32_WIDTH-1:0]                     sub_input2_shift,
    input  [INT32_WIDTH-1:0]                     sub_output_multiplier,
    input signed [INT32_WIDTH-1:0]                     sub_output_shift,
    input signed [INT32_WIDTH-1:0]                     sub_output_offset,
    input signed [31:0]                               sub_quantized_activation_min,
    input signed [31:0]                               sub_quantized_activation_max,

    // -------------------------------------
    // MUL signals
    // -------------------------------------
    input signed [INT32_WIDTH-1:0]                     mul_input1_offset,
    input signed [INT32_WIDTH-1:0]                     mul_input2_offset,
    input [INT32_WIDTH-1:0]                     mul_output_multiplier,
    input signed [INT32_WIDTH-1:0]                     mul_output_shift,
    input signed [INT32_WIDTH-1:0]                     mul_output_offset,
    input signed [31:0]                               mul_quantized_activation_min,
    input signed [31:0]                               mul_quantized_activation_max,
    
    // -------------------------------------
    // data_out
    // -------------------------------------
    output [MAX_VECTOR_SIZE * INT64_SIZE-1:0] data_out,
    output                 valid_out,
    // -------------------------------------
    // signals to op_decoder
    // -------------------------------------
    // exp
    input                                   exp_en,
    output wire                             exp_valid_out,
    input  [INT64_SIZE-1:0]                 exp_data_in,
    output wire [INT64_SIZE-1:0]            exp_data_out,
    // Reciprocal
    input                                   reciprocal_en,
    output wire                             reciprocal_valid_out,
    input  [INT64_SIZE-1:0]                 reciprocal_data_in,
    output wire [INT64_SIZE-1:0]            reciprocal_data_out,
    // Add
    input                                   add_en,
    output wire                             add_valid_out,
    input  [INT64_SIZE-1:0]                 add_data_in,
    output wire [INT64_SIZE-1:0]            add_data_out,
    input  [INT64_SIZE-1:0]                 add_weight_data_in,
    // Sub
    input                                   sub_en,
    output wire                             sub_valid_out,
    input  [INT64_SIZE-1:0]                 sub_data_in,
    output wire [INT64_SIZE-1:0]            sub_data_out,
    input  [INT64_SIZE-1:0]                 sub_weight_data_in,
    // Mul
    input                                   mul_en,
    output wire                             mul_valid_out,
    input  [INT64_SIZE-1:0]                 mul_data_in,
    output wire [INT64_SIZE-1:0]            mul_data_out,
    input  [INT64_SIZE-1:0]                 mul_weight_data_in,
    // -------------------------------------

    output [17:0] idx1_out
);
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    wire signed [INT32_WIDTH-1:0] dequant_data_in[0:MAX_VECTOR_SIZE-1]; 
    wire vec_deq_input_valid[0:MAX_VECTOR_SIZE-1];
    wire vec_output_valid[0:MAX_VECTOR_SIZE-1];
    wire vec_deq_output_valid[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] exp_tmp_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] dequant_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] exp_requant_data_o[0:MAX_VECTOR_SIZE-1];
    wire exp_requant_output_valid[0:MAX_VECTOR_SIZE-1];
    reg [17:0] ele_idx;

    // ADD , SUB, MUL signals control
    // input1 delay 1 cycle because of the other data from sram
    reg [INT64_SIZE-1:0] add_data_in_delay, sub_data_in_delay, mul_data_in_delay; 
    reg sub_en_delay, mul_en_delay, add_en_delay;
// ----------------------------------------------------
// exp 
// ----------------------------------------------------
genvar dequant_idx;
generate
    for(dequant_idx = 0; dequant_idx < MAX_VECTOR_SIZE; dequant_idx = dequant_idx + 1) begin : dequant_generate
        assign dequant_data_in[dequant_idx] = 
            (dequant_idx < groups) ?
                dequant_saturate(exp_data_in[dequant_idx*INT8_WIDTH +: INT8_WIDTH], exp_deq_input_zero_point, exp_deq_input_range_radius)
                : 0;  // 或者指定其他的default值
        assign vec_deq_input_valid[dequant_idx] = (dequant_idx < groups) ? exp_en : 0;

        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_exp_deq_inst(
            .clk(clk),
            .rst(rst),
            .x(dequant_data_in[dequant_idx]),
            .quantized_multiplier(exp_deq_input_multiplier),
            .shift(exp_deq_input_left_shift),
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
            .exp_x(exp_tmp_data_out[exp_idx]),
            .output_valid(vec_output_valid[exp_idx])
        );
    end
endgenerate
   // requant after exp finish
genvar exp_requant_idx;
generate
    for(exp_requant_idx = 0; exp_requant_idx < MAX_VECTOR_SIZE; exp_requant_idx = exp_requant_idx + 1) begin : exp_requant_vector
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_exp_req_inst(
            .clk(clk),
            .rst(rst),
            .x(exp_tmp_data_out[exp_requant_idx]),
            .quantized_multiplier(exp_req_input_quantized_multiplier),
            .shift(exp_req_input_shift),
            .input_valid(vec_output_valid[exp_requant_idx]),
            .output_valid(exp_requant_output_valid[exp_requant_idx]),
            .x_mul_by_quantized_multiplier(exp_requant_data_o[exp_requant_idx])
        );
        assign exp_data_out[exp_requant_idx*INT8_SIZE +: INT8_SIZE] = 
            ((exp_requant_data_o[exp_requant_idx] + exp_req_input_offset) >= $signed(POS_127))? $signed(POS_127):
            ((exp_requant_data_o[exp_requant_idx] + exp_req_input_offset) <= $signed(NEG_128))? $signed(NEG_128): exp_requant_data_o[exp_requant_idx][7:0] + exp_req_input_offset;
    end

endgenerate
    assign exp_valid_out = exp_requant_output_valid[0];
// -----------------------------------------------------
    // 超過input_range_radius的範圍 output直接給大小值, 這部份需要改
    // send data out(因為exp完的data是32bits, 所以都給每個data的前8個bits, 去testbench做檢查)
    // assign data_out = {exp_data_out[7][7:0], exp_data_out[6][7:0], exp_data_out[5][7:0], exp_data_out[4][7:0], exp_data_out[3][7:0], exp_data_out[2][7:0], exp_data_out[1][7:0], exp_data_out[0][7:0]};
    // assign valid_out = vec_output_valid[0];
    // assign idx1_out = ele_idx;

// ----------------------------------------------------
// reciprocal
// ----------------------------------------------------
    wire signed [INT32_WIDTH-1:0] reciprocal_dequant_data_in[0:MAX_VECTOR_SIZE-1]; 
    wire reciprocal_vec_deq_input_valid[0:MAX_VECTOR_SIZE-1];
    wire reciprocal_vec_deq_output_valid[0:MAX_VECTOR_SIZE-1];
    wire reciprocal_vec_output_valid[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] reciprocal_tmp_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] reciprocal_dequant_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] reciprocal_requant_data_o[0:MAX_VECTOR_SIZE-1];
    wire reciprocal_requant_output_valid[0:MAX_VECTOR_SIZE-1];

genvar reciprocal_dequant_idx;
generate
    for(reciprocal_dequant_idx = 0; reciprocal_dequant_idx < MAX_VECTOR_SIZE; reciprocal_dequant_idx = reciprocal_dequant_idx + 1) begin : reciprocal_dequant_generate
        assign reciprocal_dequant_data_in[reciprocal_dequant_idx] = 
            (reciprocal_dequant_idx < groups) ?
                dequant_saturate(reciprocal_data_in[reciprocal_dequant_idx*INT8_WIDTH +: INT8_WIDTH], reciprocal_deq_input_zero_point, reciprocal_deq_input_range_radius)
                : 0;
        assign reciprocal_vec_deq_input_valid[reciprocal_dequant_idx] = (reciprocal_dequant_idx < groups) ? reciprocal_en : 0;                

        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_reciprocal_deq_inst(
            .clk(clk),
            .rst(rst),
            .x(reciprocal_dequant_data_in[reciprocal_dequant_idx]),
            .quantized_multiplier(reciprocal_deq_input_multiplier),
            .shift(reciprocal_deq_input_left_shift),
            .input_valid(reciprocal_vec_deq_input_valid[reciprocal_dequant_idx]),
            .output_valid(reciprocal_vec_deq_output_valid[reciprocal_dequant_idx]),
            .x_mul_by_quantized_multiplier(reciprocal_dequant_data_out[reciprocal_dequant_idx])
        );
    end
endgenerate

    // reciprocal
genvar reciprocal_idx;
generate
    for(reciprocal_idx = 0; reciprocal_idx < MAX_VECTOR_SIZE; reciprocal_idx = reciprocal_idx + 1) begin : reciprocal_vector
        reciprocal_over_1 reciprocal_pipeline_inst (
            .clk(clk),
            .rst(rst),
            .x(reciprocal_dequant_data_out[reciprocal_idx]),
            .x_integer_bits(4'd4),
            .input_valid(reciprocal_vec_deq_output_valid[reciprocal_idx]),
            .reciprocal(reciprocal_tmp_data_out[reciprocal_idx]),
            .output_valid(reciprocal_vec_output_valid[reciprocal_idx])
        );
    end
endgenerate
    // requant after reciprocal finish
genvar reciprocal_requant_idx;
generate
    for(reciprocal_requant_idx = 0; reciprocal_requant_idx < MAX_VECTOR_SIZE; reciprocal_requant_idx = reciprocal_requant_idx + 1) begin : reciprocal_requant_vector
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_reciprocal_req_inst(
            .clk(clk),
            .rst(rst),
            .x(reciprocal_tmp_data_out[reciprocal_requant_idx]),
            .quantized_multiplier(reciprocal_req_input_quantized_multiplier),
            .shift(reciprocal_req_input_shift),
            .input_valid(reciprocal_vec_output_valid[reciprocal_requant_idx]),
            .output_valid(reciprocal_requant_output_valid[reciprocal_requant_idx]),
            .x_mul_by_quantized_multiplier(reciprocal_requant_data_o[reciprocal_requant_idx])
        );
        assign reciprocal_data_out[reciprocal_requant_idx*INT8_WIDTH +: INT8_WIDTH] = 
            ((reciprocal_requant_data_o[reciprocal_requant_idx] + reciprocal_req_input_offset) >= $signed(POS_127))? $signed(POS_127):
            ((reciprocal_requant_data_o[reciprocal_requant_idx] + reciprocal_req_input_offset) <= $signed(NEG_128))? $signed(NEG_128): reciprocal_requant_data_o[reciprocal_requant_idx][7:0] + reciprocal_req_input_offset;
    end
endgenerate
    assign reciprocal_valid_out = reciprocal_requant_output_valid[0];
// ----------------------------------------------------

    // ADD, SUB, MUL for delay 1 cycle
    // always @(posedge clk)begin
    //     if(!rst)begin
    //         add_data_in_delay <= 0;
    //         sub_data_in_delay <= 0;
    //         mul_data_in_delay <= 0;
    //         add_en_delay <= 0;
    //         sub_en_delay <= 0;
    //         mul_en_delay <= 0;
    //     end else begin
    //         add_data_in_delay <= add_data_in;
    //         sub_data_in_delay <= sub_data_in;
    //         mul_data_in_delay <= mul_data_in;
    //         add_en_delay <= add_en;
    //         sub_en_delay <= sub_en;
    //         mul_en_delay <= mul_en;
    //     end
    // end
    // -------------------------------------
    // ADD control, take weight from sram
    // always @(posedge clk)begin
    //     if(!rst)begin
    //         add_weight_addr_out <= 0;
    //     end else if(add_en)begin
    //         add_weight_addr_out <= add_weight_addr_out + groups; // depend on how many groups of each mac output
    //     end
    // end

    ADD add_inst
    (
        .clk(clk),
        .rst(rst),
        .valid_in(add_en),
        .input1(add_data_in),
        .input2(add_weight_data_in),
        .input1_offset(add_input1_offset),
        .input2_offset(add_input2_offset),
        .left_shift(add_left_shift),
        .input1_multiplier(add_input1_multiplier),
        .input2_multiplier(add_input2_multiplier),
        .input1_shift(add_input1_shift),
        .input2_shift(add_input2_shift),
        .output_multiplier(add_output_multiplier),
        .output_shift(add_output_shift),
        .output_offset(add_output_offset),
        .quantized_activation_min(add_quantized_activation_min),
        .quantized_activation_max(add_quantized_activation_max),
        .data_o(add_data_out),
        .valid_o(add_valid_out)
    );
    // -------------------------------------
    // SUB control, take weight from sram
    // always @(posedge clk)begin
    //     if(!rst)begin
    //         sub_weight_addr_out <= 0;
    //     end else if(sub_en)begin
    //         sub_weight_addr_out <= sub_weight_addr_out + groups; // depend on how many groups of each mac output
    //     end
    // end

    SUB sub_inst
    (
        .clk(clk),
        .rst(rst),
        .valid_in(sub_en),
        .input1(sub_data_in),
        .input2(sub_weight_data_in),
        // .input1(sub_weight_data_in),
        // .input2(sub_data_in),
        .input1_offset(sub_input1_offset),
        .input2_offset(sub_input2_offset),
        .left_shift(sub_left_shift),
        .input1_multiplier(sub_input1_multiplier),
        .input2_multiplier(sub_input2_multiplier),
        .input1_shift(sub_input1_shift),
        .input2_shift(sub_input2_shift),
        .output_multiplier(sub_output_multiplier),
        .output_shift(sub_output_shift),
        .output_offset(sub_output_offset),
        .quantized_activation_min(sub_quantized_activation_min),
        .quantized_activation_max(sub_quantized_activation_max),
        .data_o(sub_data_out),
        .valid_o(sub_valid_out)
    );
    // -------------------------------------
    // MUL control, take weight from sram
    // always @(posedge clk)begin
    //     if(!rst)begin
    //         mul_weight_addr_out <= 0;
    //     end else if(mul_en)begin
    //         mul_weight_addr_out <= mul_weight_addr_out + groups; // depend on how many groups of each mac output
    //     end
    // end

    MUL mul_inst
    (
        .clk(clk),
        .rst(rst),
        .valid_in(mul_en),
        .input1(mul_data_in),
        .input2(mul_weight_data_in),
        .input1_offset(mul_input1_offset),
        .input2_offset(mul_input2_offset),
        .output_multiplier(mul_output_multiplier),
        .output_shift(mul_output_shift),
        .output_offset(mul_output_offset),
        .quantized_activation_min(mul_quantized_activation_min),
        .quantized_activation_max(mul_quantized_activation_max),
        .data_o(mul_data_out),
        .valid_o(mul_valid_out)
    );
    // -------------------------------------

    always @(posedge clk)begin
        if(!rst)begin
            ele_idx <= 0;
        end else if(init) begin
            ele_idx <= 0;
        end else if(valid_out)begin
            // $display("%0t: Output valid. ele_idx[%d]=%h, ele_idx[%d]=%h", $time, 2*ele_idx, exp_data_out[0],2*ele_idx+1, exp_data_out[1]);
            ele_idx <= ele_idx + 1;
        end 
    end

    // DEBUG INFO
    always @(posedge clk)begin
        // if(sub_en)begin
        //     $display("[SUB] data_in: %h, weight_data_in: %h", sub_data_in, sub_weight_data_in);
        // end
        if(exp_valid_out)begin
            $display("[EXP] data_out: %h", exp_data_out);
        end
        if(reciprocal_valid_out)begin
            $display("[RECIPROCAL] data_out: %h", reciprocal_data_out);
        end
    end

endmodule  // element_wise

