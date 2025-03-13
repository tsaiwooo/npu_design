// RoundingDivideByPOT(SaturatingRoundingDoublingHighMul(x * (1 << left_shift), quantized_multiplier), right_shift)
// left_shift 是因為2^shift shift是正數, 表示除以一個小於1的數, 所以先左移
// 1~4 處理SaturatingRoundingDoublingHighMul_ret = SaturatingRoundingDoublingHighMul(x * (1 << left_shift), quantized_multiplier)
// 5~x 處理RoundingDivideByPOT_ret = RoundingDivideByPOT(SaturatingRoundingDoublingHighMul_ret, right_shift)
// 1. input (x, quantized_multiplier, left_shift)
    // 1.1 x * (1 << left_shift)
// 2. 
    // 2.1 overflow? (overflow = a == b && a == std::numeric_limits<std::int32_t>::min();), 
    // 2.2 ab_64 = a_64*b_64, 
// 3. 
    // 3.1 nudge = (ab_64 >=0)? (1<<30): (1 - (1<<30)),
    // 3.2 取出ab_64的高32位，加上nudge再左移31位 (ab_x2_high32 = static_cast<std::int32_t>((ab_64 + nudge) / (1ll << 31)))
// 4.
    // 4.1 overflow?, max(): ab_x2_high32
// 5. input (SaturatingRoundingDoublingHighMul_ret, right_shift)
    // 5.1 確保 31 >= right_shift >= 0,
    // 5.2 mask = (1 << right_shift) - 1
    // 5.3 zero = 0
    // 5.4 one = 1
    // 5.5 計算出remainder = ab_x2_high32 & mask( (1<<right_shift) - 1) 
    // 5.6 計算出threshold = mask >> 1 + (ab_x2_high32 < 0) -> ab_x2_high32 < 0返回全1，否則返回0
// 6.
    // 6.1 q = ab_x2_high32 >> right_shift + ((remainder > threshold) || (remainder == threshold && (ab_x2_high32 & 1) && ab_x2_high32 != 32'h7fffffff))

`timescale 1ns / 1ps
`include "params.vh"

module MultiplyByQuantizedMultiplier
(
    input clk,
    input rst,
    input signed [31:0] x,
    input signed [31:0] quantized_multiplier,
    input signed [31:0] shift,
    input input_valid,
    output reg output_valid,
    output reg signed [31:0] x_mul_by_quantized_multiplier
);
    // reg signed [7:0] x_mul_by_quantized_multiplier;
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    // pipeline total stages from dequant_valid_in to exp_valid_out,但是在tflm中是一開始就判斷好存好
    // 所以需要真正的stages, 也就是說看完整的運算式多少個cycles再加上去
    // Pipeline stage valid signals
    reg valid_stage1, valid_stage2, valid_stage3, valid_stage4;

    // Pipeline registers for input and intermediate values
    reg signed [31:0] x_reg_s1, quantized_multiplier_reg_s1;
    reg signed [31:0] left_shift_s1, right_shift_s1, right_shift_s2, right_shift_s3, right_shift_s4;
    reg signed [63:0] ab_64_s1, ab_64_s2, ab_64_s3;
    reg overflow_s1, overflow_s2, overflow_s3;
    reg signed [30:0] nudge_s3;
    reg signed [31:0] ab_x2_high32_s3, ab_x2_high32_s4;
    reg  [31:0] remainder_s4, threshold_s4;

    // Combinational logic for shift calculation
    wire [31:0] left_shift_wire, right_shift_wire;
    assign left_shift_wire = (shift > 0) ? shift : 0;
    assign right_shift_wire = (shift > 0) ? 0 : -shift;

    // right_shift > 0, 判斷是否overflow
    reg [1:0] right_shift_overflow_s3, right_shift_overflow_s4;

    // Stage 1: Input registration and initial multiplication
    always @(posedge clk) begin
        if (!rst) valid_stage1 <= 0;
        else valid_stage1 <= input_valid;
    end

    always @(posedge clk) begin
        if (!rst) x_reg_s1 <= 0;
        else if (input_valid) x_reg_s1 <= x;
    end

    always @(posedge clk) begin
        if (!rst) quantized_multiplier_reg_s1 <= 0;
        else if (input_valid) quantized_multiplier_reg_s1 <= quantized_multiplier;
    end

    always @(posedge clk) begin
        if (!rst) left_shift_s1 <= 0;
        else if (input_valid) left_shift_s1 <= left_shift_wire;
    end

    always @(posedge clk) begin
        if (!rst) right_shift_s1 <= 0;
        else if (input_valid) right_shift_s1 <= right_shift_wire;
    end

    always @(posedge clk) begin
        if (!rst) ab_64_s1 <= 0;
        else if (input_valid) ab_64_s1 <= x * (1 << left_shift_wire);
    end

    always @(posedge clk) begin
        if (!rst) overflow_s1 <= 0;
        else if (input_valid) overflow_s1 <= (x == quantized_multiplier && x == 32'h80000000);
    end

    // Stage 2: Multiplication with quantized_multiplier
    always @(posedge clk) begin
        if (!rst) valid_stage2 <= 0;
        else valid_stage2 <= valid_stage1;
    end

    always @(posedge clk) begin
        if (!rst) ab_64_s2 <= 0;
        else if (valid_stage1) ab_64_s2 <= ab_64_s1 * quantized_multiplier_reg_s1;
    end

    always @(posedge clk) begin
        if (!rst) overflow_s2 <= 0;
        else if (valid_stage1) overflow_s2 <= overflow_s1;
    end

    always @(posedge clk) begin
        if (!rst) right_shift_s2 <= 0;
        else if (valid_stage1) right_shift_s2 <= right_shift_s1;
    end

    // Stage 3: Nudge calculation and high 32 bits extraction
    always @(posedge clk) begin
        if (!rst) valid_stage3 <= 0;
        else valid_stage3 <= valid_stage2;
    end

    always @(posedge clk) begin
        if (!rst) nudge_s3 <= 0;
        else if (valid_stage2) nudge_s3 <= (ab_64_s2 >= 0) ? (1 << 30) : (1 - (1 << 30));
    end

    // always @(posedge clk) begin
    //     if (!rst) ab_x2_high32_s3 <= 0;
    //     else if (valid_stage2) ab_x2_high32_s3 <= overflow_s2 ? 32'h7FFFFFFF : ((ab_64_s2 + nudge_s3) >>> 31);
    // end

    always @(posedge clk) begin
        if (!rst) ab_64_s3 <= 0;
        else if(valid_stage2) ab_64_s3 <= ab_64_s2;
    end

    always @(posedge clk) begin
        if (!rst) overflow_s3 <= 0;
        else if (valid_stage2) overflow_s3 <= overflow_s2;
    end

    always @(posedge clk) begin
        if (!rst) right_shift_s3 <= 0;
        else if (valid_stage2) right_shift_s3 <= right_shift_s2;
    end

    // 檢查是否overflow
    wire [63:0] NEG_128_SHIFT = NEG_128 <<< right_shift_s2;
    wire [63:0] POS_127_SHIFT = POS_127 <<< right_shift_s2;

    always @(posedge clk)begin
        if(!rst) right_shift_overflow_s3 <= 0;
        else if(valid_stage2)begin
            if(right_shift_s2 > 0)begin
                if($signed(ab_64_s2[63-:32]) < $signed(NEG_128_SHIFT))begin
                    right_shift_overflow_s3 <= 2'd1;
                end else if($signed(ab_64_s2[63-:32]) > $signed(POS_127_SHIFT))begin
                    right_shift_overflow_s3 <= 2'd2;
                end else begin
                    right_shift_overflow_s3 <= 2'd0;
                end
            end else begin
                right_shift_overflow_s3 <= 0;
            end
        end
    end

    // Stage 4: Remainder and threshold calculation
    wire signed [31:0] ab_x3_high32;
    assign ab_x3_high32 = overflow_s3 ? 32'h7FFFFFFF : ((ab_64_s3 + nudge_s3) >>> 31);

    always @(posedge clk) begin
        if (!rst) valid_stage4 <= 0;
        else valid_stage4 <= valid_stage3;
    end

    always @(posedge clk) begin
        if (!rst) remainder_s4 <= 0;
        else if (valid_stage3) remainder_s4 <= ab_x3_high32 & ((1 << right_shift_s3) - 1);
    end

    always @(posedge clk) begin
        if (!rst) threshold_s4 <= 0;
        else if (valid_stage3) threshold_s4 <= (((1 << right_shift_s3) - 1) >> 1) + ((ab_x3_high32 < 0) ? 1 : 0);
    end

    always @(posedge clk) begin
        if (!rst) ab_x2_high32_s4 <= 0;
        else if (valid_stage3) ab_x2_high32_s4 <= ab_x3_high32;
    end

    always @(posedge clk) begin
        if (!rst) right_shift_s4 <= 0;
        else if (valid_stage3) right_shift_s4 <= right_shift_s3;
    end

    always @(posedge clk) begin
        if(!rst) right_shift_overflow_s4 <= 0;
        else if(valid_stage3) begin
            right_shift_overflow_s4 <= right_shift_overflow_s3;
        end
    end
    // Stage 5: Final calculation and output
    always @(posedge clk) begin
        if (!rst) output_valid <= 0;
        else output_valid <= valid_stage4;
    end
    
    wire signed [31:0] tmp_result;
    assign tmp_result = (ab_x2_high32_s4 >>> right_shift_s4);
    always @(posedge clk) begin
        if (!rst) x_mul_by_quantized_multiplier <= 0;
        else if (valid_stage4) begin
            if(right_shift_overflow_s4 == 2'd2)begin
                x_mul_by_quantized_multiplier <= POS_127;
            end else if(right_shift_overflow_s4 == 2'd1)begin
                x_mul_by_quantized_multiplier <= NEG_128;
            end else begin 
                // x_mul_by_quantized_multiplier <= (ab_x2_high32_s4 >>> right_shift_s4);
                // tmp_result = (ab_x2_high32_s4 >>> right_shift_s4);
                if (remainder_s4 > threshold_s4) begin
                    // x_mul_by_quantized_multiplier <= (ab_x2_high32_s4 >>> right_shift_s4) + 1;
                    x_mul_by_quantized_multiplier <= (tmp_result >= $signed(POS_127))? $signed(POS_127) : 
                                                    (tmp_result < $signed(NEG_128))? $signed(NEG_128) : tmp_result + 1;
                end else begin
                    x_mul_by_quantized_multiplier <= tmp_result;
                end
            end
        end
    end
endmodule
