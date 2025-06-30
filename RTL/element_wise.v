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
    input        [3:0]     groups,
    input signed [INT64_SIZE-1:0]                      data_in,
    input signed [INT64_SIZE-1:0]                      weight_data_in,
    input [2:0]            broadcast,
    // input                                       valid_in,
    input [MAX_ADDR_WIDTH-1:0]                  output_data_counts_i,
    // -------------------------------------
    // exp_data_in, 之後看哪個element-wise的function要啟用就增加port
    // -------------------------------------
    input [INT32_WIDTH-1:0]                            exp_deq_input_range_radius,
    input signed [INT32_WIDTH-1:0]                     exp_deq_input_zero_point,
    input signed [INT32_WIDTH-1:0]                     exp_deq_input_left_shift,
    input signed [INT32_WIDTH-1:0]                     exp_deq_input_multiplier,
    input signed [INT32_WIDTH-1:0]                     exp_req_input_quantized_multiplier,
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

    // Element-wise addr & sram_em
    output reg [MAX_ADDR_WIDTH-1:0]                     ele_data_addr_o,
    output wire                                         ele_sram_en,
    // -------------------------------------
    // signals to op_decoder
    // -------------------------------------
    input                                   exp_en,
    input                                   reciprocal_en,
    input                                   add_en,
    input                                   sub_en,
    input                                   mul_en,
    // -------------------------------------

    // -------------------------------------
    // ele_data_out
    // -------------------------------------
    output reg [INT64_SIZE-1:0] ele_data_out,
    output                 ele_valid_out,
    output reg [31:0] ele_valid_in_counts,
    output reg [31:0] ele_results_counts
);
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    wire signed [INT32_WIDTH-1:0] exp_dequant_data_in[0:MAX_VECTOR_SIZE-1],reciprocal_dequant_data_in[0:MAX_VECTOR_SIZE-1]; 
    wire signed [INT32_WIDTH-1:0] exp_dequant_data_out[0:MAX_VECTOR_SIZE-1],reciprocal_dequant_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_WIDTH-1:0] exp_data_out[0:MAX_VECTOR_SIZE-1],reciprocal_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT32_SIZE-1:0] exp_req_data_out[0:MAX_VECTOR_SIZE-1],reciprocal_req_data_out[0:MAX_VECTOR_SIZE-1];
    wire signed [INT8_SIZE-1:0] exp_result[0:MAX_VECTOR_SIZE-1],reciprocal_result[0:MAX_VECTOR_SIZE-1];
    wire exp_deq_output_valid[0:MAX_VECTOR_SIZE-1], reciprocal_deq_output_valid[0:MAX_VECTOR_SIZE-1];
    wire exp_output_valid[0:MAX_VECTOR_SIZE-1], reciprocal_output_valid[0:MAX_VECTOR_SIZE-1];
    wire exp_req_valid_out[0:MAX_VECTOR_SIZE-1], reciprocal_req_valid_out[0:MAX_VECTOR_SIZE-1];
    wire [INT64_SIZE-1:0] add_data_out,sub_data_out,mul_data_out;
    wire sub_valid_out,add_valid_out,mul_valid_out;
    assign ele_valid_out = exp_req_valid_out[0] | reciprocal_req_valid_out[0] | add_valid_out | sub_valid_out | mul_valid_out;

    reg exp_en_delay, reciprocal_en_delay, add_en_delay, sub_en_delay, mul_en_delay;
    reg exp_en_delay2, reciprocal_en_delay2, add_en_delay2, sub_en_delay2, mul_en_delay2;
    wire add_en_sel, sub_en_sel, mul_en_sel;
    assign add_en_sel = (broadcast > 0)? add_en_delay2 : add_en_delay;
    assign sub_en_sel = (broadcast > 0)? sub_en_delay2 : sub_en_delay;
    assign mul_en_sel = (broadcast > 0)? mul_en_delay2 : mul_en_delay;

    wire [MAX_ADDR_WIDTH-1:0] ele_counter_en;
    assign ele_counter_en = exp_en | reciprocal_en | add_en | sub_en | mul_en;
    assign ele_sram_en = ele_counter_en && (ele_data_addr_o < output_data_counts_i);
    // ele_data_out
    always @(*) begin
        if(exp_req_valid_out[0])begin
            ele_data_out = {exp_result[7], exp_result[6], exp_result[5], exp_result[4],
                        exp_result[3], exp_result[2], exp_result[1], exp_result[0]};
        end else if(reciprocal_req_valid_out[0])begin
            ele_data_out = {reciprocal_result[7], reciprocal_result[6], reciprocal_result[5], reciprocal_result[4],
                        reciprocal_result[3], reciprocal_result[2], reciprocal_result[1], reciprocal_result[0]};
        end else if(add_valid_out)begin
            ele_data_out = add_data_out;
        end else if(sub_valid_out)begin
            ele_data_out = sub_data_out;
        end else if(mul_valid_out)begin
            ele_data_out = mul_data_out;
        end else begin
            ele_data_out = 0;
        end
    end

    // control ele_data_addr_o:
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            ele_data_addr_o <= 0;
        end else if(init) begin
            ele_data_addr_o <= 0;
        end else if(ele_counter_en) begin
            ele_data_addr_o <= ele_data_addr_o + 8;
        end
    end
    
    // delay for data coming
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            exp_en_delay <= 0;
            reciprocal_en_delay <= 0;
            add_en_delay <= 0;
            sub_en_delay <= 0;
            mul_en_delay <= 0;
        end else if(init) begin
            exp_en_delay <= 0;
            reciprocal_en_delay <= 0;
            add_en_delay <= 0;
            sub_en_delay <= 0;
            mul_en_delay <= 0;
        end else begin
            exp_en_delay <= exp_en;
            reciprocal_en_delay <= reciprocal_en;
            add_en_delay <= add_en;
            sub_en_delay <= sub_en;
            mul_en_delay <= mul_en;
        end
    end

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            exp_en_delay2 <= 0;
            reciprocal_en_delay2 <= 0;
            add_en_delay2 <= 0;
            sub_en_delay2 <= 0;
            mul_en_delay2 <= 0;
        end else if(init) begin
            exp_en_delay2 <= 0;
            reciprocal_en_delay2 <= 0;
            add_en_delay2 <= 0;
            sub_en_delay2 <= 0;
            mul_en_delay2 <= 0;
        end else begin
            exp_en_delay2 <= exp_en_delay;
            reciprocal_en_delay2 <= reciprocal_en_delay;
            add_en_delay2 <= add_en_delay;
            sub_en_delay2 <= sub_en_delay;
            mul_en_delay2 <= mul_en_delay;
        end
    end
    // -----------------------------------------
    // exp: dequant -> exp -> requant
    // -----------------------------------------
    // dequant
genvar i;
generate
    for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin: exp_vec
        assign exp_dequant_data_in[i] = dequant_saturate(
        data_in[i*INT8_WIDTH +: INT8_WIDTH],
        exp_deq_input_zero_point, 
        exp_deq_input_range_radius
        );
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_gemm_inst(
            .clk(clk),
            .rst(rst),
            .x(exp_dequant_data_in[i]),
            .quantized_multiplier(exp_deq_input_multiplier),
            .shift(exp_deq_input_left_shift),
            .input_valid(exp_en_delay),
            .output_valid(exp_deq_output_valid[i]),
            .x_mul_by_quantized_multiplier(exp_dequant_data_out[i])
        );

        // exp
        exp_pipeline exp_pipeline_inst (
            .clk(clk),
            .rst(rst),
            .x(exp_dequant_data_out[i]),
            .input_valid(exp_deq_output_valid[i]),
            .integer_bits(4'd4),
            .exp_x(exp_data_out[i]),
            .output_valid(exp_output_valid[i])
        );
        // exp requantization
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_exp_req_inst(
            .clk(clk),
            .rst(rst),
            .x(exp_data_out[i]),
            .quantized_multiplier(exp_req_input_quantized_multiplier),
            .shift(exp_req_input_shift),
            .input_valid(exp_output_valid[i]),
            .output_valid(exp_req_valid_out[i]),
            .x_mul_by_quantized_multiplier(exp_req_data_out[i])
        );
        assign exp_result[i] = ((exp_req_data_out[i] + exp_req_input_offset)  > $signed(POS_127)) ? $signed(POS_127) :
                            ((exp_req_data_out[i] + exp_req_input_offset)  < $signed(NEG_128)) ? $signed(NEG_128) :
                            (exp_req_data_out[i] + exp_req_input_offset);
    end
endgenerate

    // -------------------------------------
    // Reciprocal: dequant -> reciprocal -> requant
    // -------------------------------------
    // dequant
generate
    for(i = 0; i < MAX_VECTOR_SIZE; i = i+1) begin : reciprocal_vec
        assign reciprocal_dequant_data_in[i] = dequant_saturate(
            data_in[i*INT8_WIDTH +: INT8_WIDTH], 
            reciprocal_deq_input_zero_point, 
            reciprocal_deq_input_range_radius
        );
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_reciprocal_inst(
            .clk(clk),
            .rst(rst),
            .input_valid(reciprocal_en_delay),
            .x(reciprocal_dequant_data_in[i]),
            .quantized_multiplier(reciprocal_deq_input_multiplier),
            .shift(reciprocal_deq_input_left_shift),
            .output_valid(reciprocal_deq_output_valid[i]),
            .x_mul_by_quantized_multiplier(reciprocal_dequant_data_out[i])
        );
        // reciprocal
        reciprocal_over_1 Reciprocal_inst (
            .clk(clk),
            .rst(rst),
            .x(reciprocal_dequant_data_out[i]),
            .x_integer_bits(4'd4),
            .input_valid(reciprocal_deq_output_valid[i]),
            .reciprocal(reciprocal_data_out[i]),
            .output_valid(reciprocal_output_valid[i])
        );
        // reciprocal requantization
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_reciprocal_req_inst(
            .clk(clk),
            .rst(rst),
            .x(reciprocal_data_out[i]),
            .quantized_multiplier(reciprocal_req_input_quantized_multiplier),
            .shift(reciprocal_req_input_shift),
            .input_valid(reciprocal_output_valid[i]),
            .output_valid(reciprocal_req_valid_out[i]),
            .x_mul_by_quantized_multiplier(reciprocal_req_data_out[i])
        );
        assign reciprocal_result[i] = ((reciprocal_req_data_out[i] + reciprocal_req_input_offset) > $signed(POS_127)) ? $signed(POS_127) :
                                    ((reciprocal_req_data_out[i] + reciprocal_req_input_offset) < $signed(NEG_128)) ? $signed(NEG_128) :
                                    (reciprocal_req_data_out[i] + reciprocal_req_input_offset);
    end
endgenerate

    // -------------------------------------
    // ADD
    // -------------------------------------
    ADD add_inst(
        .clk(clk),
        .rst(rst),
        .valid_in(add_en_sel),
        .input1(data_in),
        .input2(weight_data_in),
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

    // ----------------------------------
    // SUB
    // ----------------------------------
    SUB sub_inst(
        .clk(clk),
        .rst(rst),
        .valid_in(sub_en_sel),
        .input1(data_in),
        .input2(weight_data_in),
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

    // ----------------------------------
    // MUL
    // ----------------------------------
    MUL mul_inst(
        .clk(clk),
        .rst(rst),
        .valid_in(mul_en_sel),
        .input1(data_in),
        .input2(weight_data_in),
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
    // 超過input_range_radius的範圍 output直接給大小值, 這部份需要改
    // send data out(因為exp完的data是32bits, 所以都給每個data的前8個bits, 去testbench做檢查)
    // assign ele_data_out = exp_data_out[7:0];
    // assign ele_valid_out = exp_output_valid;

    always @(posedge clk)begin
        if(!rst)begin
            ele_results_counts <= 0;
        end else if(init) begin
            ele_results_counts <= 0;
        end else if(ele_valid_out)begin
            ele_results_counts <= ele_results_counts + 1'b1;
        end
    end

    always @(posedge clk)begin
        if(!rst)begin
            ele_valid_in_counts <= 0;
        end else if(init) begin
            ele_valid_in_counts <= 0;
        end else if(exp_en | reciprocal_en | sub_en | add_en | mul_en)begin
            ele_valid_in_counts <= ele_valid_in_counts + 1'b1;
        end
    end

endmodule  // element_wise

