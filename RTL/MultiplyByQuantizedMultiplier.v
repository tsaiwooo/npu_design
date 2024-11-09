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
    input [31:0] x,
    input [31:0] quantized_multiplier,
    input  signed [31:0] shift,
    input input_valid,
    output reg output_valid,
    output reg [31:0] x_mul_by_quantized_multiplier
);
    localparam IDLE = 0, LOAD = 1, 
               SaturatingRoundingDoublingHighMul_1 = 2, 
               SaturatingRoundingDoublingHighMul_2 = 3,
               RoundingDivideByPOT_1 = 4,
               RoundingDivideByPOT_2 = 5,
               OUTPUT = 6;

    reg [3:0] state, next_state;
    reg [31:0] x_reg, quantized_multiplier_reg, shift_reg;
    reg signed [63:0] ab_64; 
    reg signed [31:0] ab_x2_high32;
    reg [31:0] nudge;
    reg [31:0] left_shift, right_shift;
    reg [31:0] remainder, threshold;
    wire overflow;

    // calculate left_shift and right_shift
    assign left_shift = (shift > 0) ? shift : 0;
    assign right_shift = (shift > 0) ? 0 : -shift;
    assign overflow = (x_reg == quantized_multiplier_reg && x_reg == 32'h80000000);

    // FSM
    always @(*) begin
        case (state)
            IDLE: next_state = (input_valid) ? LOAD : IDLE;
            LOAD: next_state = SaturatingRoundingDoublingHighMul_1;
            SaturatingRoundingDoublingHighMul_1: next_state = SaturatingRoundingDoublingHighMul_2;
            SaturatingRoundingDoublingHighMul_2: next_state = RoundingDivideByPOT_1;
            RoundingDivideByPOT_1: next_state = RoundingDivideByPOT_2;
            RoundingDivideByPOT_2: next_state = OUTPUT;
            OUTPUT: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // input_valid
    always @(posedge clk) begin
        if (!rst) begin
            x_reg <= 0;
            quantized_multiplier_reg <= 0;
            shift_reg <= 0;
        end else if (input_valid) begin
            x_reg <= x;
            quantized_multiplier_reg <= quantized_multiplier;
            shift_reg <= shift;
        end
    end

    // FSM control
    always @(posedge clk) begin
        if (!rst) begin
            ab_64 <= 0;
            nudge <= 0;
            ab_x2_high32 <= 0;
            remainder <= 0;
            threshold <= 0;
            output_valid <= 0;
            x_mul_by_quantized_multiplier <= 0;
        end else begin
            case (state)
                LOAD: begin
                    // 1.  x * (1 << left_shift)
                    ab_64 <= x_reg * (1 << left_shift);
                end
                SaturatingRoundingDoublingHighMul_1: begin
                    // 2. overflow
                    // if (overflow) begin
                    //     ab_64 <= 32'h7FFFFFFF;  // max
                    //     $display("in unit test Overflow detected---------------------------------------");
                    // end
                    // else
                        ab_64 <= ab_64 * quantized_multiplier_reg;  // mul by quantized_multiplier
                end
                SaturatingRoundingDoublingHighMul_2: begin
                    // 3. calculate nudge 
                    nudge <= (ab_64 >= 0) ? (1 << 30) : (1 - (1 << 30));
                    ab_x2_high32 <= overflow? 32'h7FFFFFFF : (ab_64 + nudge) >> 31;
                end
                RoundingDivideByPOT_1: begin
                    // 5.1 check right_shift is valid
                    if (right_shift >= 0 && right_shift <= 31) begin
                        // 5.2 calculate remainder and threshold
                        remainder <= ab_x2_high32 & ((1 << right_shift) - 1);
                        threshold <= ((1 << right_shift) - 1) >> 1;
                        if (ab_x2_high32 < 0)
                            threshold <= threshold + 1;
                    end
                end
                RoundingDivideByPOT_2: begin
                    // 6. operation q = ab_x2_high32 >> right_shift + ((remainder > threshold) || (remainder == threshold && (ab_x2_high32 & 1)))
                    x_mul_by_quantized_multiplier <= (ab_x2_high32 >> right_shift);
                    if (remainder > threshold || 
                        (remainder == threshold && (ab_x2_high32 & 1) && ab_x2_high32 != 32'h7fffffff))
                        x_mul_by_quantized_multiplier <= x_mul_by_quantized_multiplier + 1;
                end
                OUTPUT: begin
                    // output valid
                    output_valid <= 1;
                end
                default: begin
                    output_valid <= 0;
                end
            endcase
        end
    end

endmodule