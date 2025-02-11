// logistic(FixedPoint4::FromRaw(input_in_q4)).raw()

// // Returns logistic(x) = 1 / (1 + exp(-x)) for x > 0.
// template <typename tRawType, int tIntegerBits>
// FixedPoint<tRawType, 0> logistic_on_positive_values(
//     FixedPoint<tRawType, tIntegerBits> a) {
//   return one_over_one_plus_x_for_x_in_0_1(exp_on_negative_values(-a));
// }
// exp_on_negative_values -> exp(-x)
// one_over_one_plus_x_for_x_in_0_1 -> 1 / (1 + x)

`timescale 1ns / 1ps
`include "params.vh"

module exp_pipeline(
    input  clk,
    input  rst,
    input  signed [31:0] x,
    input  [3:0] integer_bits,
    input  input_valid,
    output reg [31:0] exp_x,
    output reg output_valid
);

    // Multiplier constants for Taylor series expansion for e^x
    // localparam signed [15:0] multiplier_0 = 16'b1000000000000000;  // 1/2
    // localparam signed [15:0] multiplier_1 = 16'b0010101010101010;  // approx 1/6
    // localparam signed [15:0] multiplier_2 = 16'b0000101010101010;  // approx 1/24
    // localparam signed [15:0] multiplier_3 = 16'b0000001000100010;  // approx 1/120
    // localparam signed [15:0] multiplier_4 = 16'b0000000011001100;  // approx 1/720
    localparam signed [15:0] multiplier_0 = 16'b0100000000000000;  // 1/2
    localparam signed [15:0] multiplier_1 = 16'b0010101010101101;  // approx 1/3
    localparam signed [15:0] multiplier_2 = 16'b0010000000000000;  // approx 1/4
    localparam signed [15:0] multiplier_3 = 16'b0001100110011010;  // approx 1/5
    localparam signed [15:0] multiplier_4 = 16'b0001010101010101;  // approx 1/6

    // Pipeline registers
    reg signed [43:0] x_extention_stage1, x_extention_stage2, x_extention_stage3, x_extention_stage4, x_extention_stage5;
    reg signed [87:0] x_power_stage2, x_power_stage3, x_power_stage4, x_power_stage5;
    reg signed [87:0] term1, term2, term3, term4, term5;
    reg signed [87:0] temp_stage1, temp_stage2, temp_stage3, temp_stage4, temp_stage5;
    reg signed [87:0] final_result;

    // Valid signal propagation through the pipeline
    reg valid_stage1, valid_stage2, valid_stage3, valid_stage4, valid_stage5, valid_stage6, valid_stage7;

    // Stage 1: Initialize x_extention_stage1 when input is valid
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage1 <= 0;
        end else if (input_valid) begin
            // x_extention_stage1 <= {{12{x[31]}}, x[30:0]} << integer_bits; // Extend to Q12.31
            x_extention_stage1 <= $signed(x) << integer_bits; // Extend to Q12.31
            // x_extention_stage1 <= { 12'b1, x } <<< 12; // Extend to Q12.31
            // x_extention_stage1 <= { {8{x[31]}} , x , 4'b0 }; // Extend to Q12.31
        end
    end

    // Stage 1: Initialize term1
    always @(posedge clk) begin
        if (!rst) begin
            term1 <= 0;
        end else if (input_valid) begin
            // term1 <= {{12{x[31]}}, x[30:0]} << integer_bits; // Initial term
            term1 <= $signed(x) << integer_bits; // Initial term
            // term1 <= { 12'b1, x } <<< 12; // Extend to Q12.31
            // term1 <= { {8{x[31]}} , x ,4'b0 }; // Extend to Q12.31
        end
    end

    // Stage 1: Initialize temp_stage1 to 1 in Q0.31
    always @(posedge clk) begin
        if (!rst) begin
            temp_stage1 <= 64'd1 << 31;
        end
    end

    // Stage 1: Valid signal for stage 1
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage1 <= 0;
        end else begin
            valid_stage1 <= input_valid;
        end
    end

    // Stage 2: Compute x_extention_stage2
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage2 <= 0;
        end else if (valid_stage1) begin
            x_extention_stage2 <= x_extention_stage1;
        end
    end

    // Stage 2: Compute x_power_stage2 as x^2
    always @(posedge clk) begin
        if (!rst) begin
            x_power_stage2 <= 0;
        end else if (valid_stage1) begin
            x_power_stage2 <= (x_extention_stage1 * x_extention_stage1) >>> 31;
        end
    end

    // Stage 2: Compute term2 for x^2 * 1/2
    always @(posedge clk) begin
        if (!rst) begin
            term2 <= 0;
        end else if (valid_stage1) begin
            term2 <= (x_extention_stage1 * x_extention_stage1 * multiplier_0) >>> 46;
        end
    end

    // Stage 2: Compute temp_stage2 with subtraction
    always @(posedge clk) begin
        if (!rst) begin
            temp_stage2 <= 0;
        end else if (valid_stage1) begin
            temp_stage2 <= temp_stage1 + term1;
        end
    end

    // Stage 2: Valid signal for stage 2
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage2 <= 0;
        end else begin
            valid_stage2 <= valid_stage1;
        end
    end

    // Stage 3: Compute x_extention_stage3
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage3 <= 0;
        end else if (valid_stage2) begin
            x_extention_stage3 <= x_extention_stage2;
        end
    end

    // Stage 3: Compute x_power_stage3 as x^3
    always @(posedge clk) begin
        if (!rst) begin
            x_power_stage3 <= 0;
        end else if (valid_stage2) begin
            x_power_stage3 <= (x_power_stage2 * x_extention_stage2) >>> 31;
        end
    end

    // Stage 3: Compute term3 for x^3 * 1/6
    always @(posedge clk) begin
        if (!rst) begin
            term3 <= 0;
        end else if (valid_stage2) begin
            term3 <= (x_power_stage2 * x_extention_stage2 * multiplier_1) >>> 46;
        end
    end

    // Stage 3: Compute temp_stage3 with addition
    always @(posedge clk) begin
        if (!rst) begin
            temp_stage3 <= 0;
        end else if (valid_stage2) begin
            temp_stage3 <= temp_stage2 + term2;
        end
    end

    // Stage 3: Valid signal for stage 3
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage3 <= 0;
        end else begin
            valid_stage3 <= valid_stage2;
        end
    end

    // Stage 4: Compute x_extention_stage4
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage4 <= 0;
        end else if (valid_stage3) begin
            x_extention_stage4 <= x_extention_stage3;
        end
    end

    // Stage 4: Compute x_power_stage4 as x^4
    always @(posedge clk) begin
        if (!rst) begin
            x_power_stage4 <= 0;
        end else if (valid_stage3) begin
            x_power_stage4 <= (x_power_stage3 * x_extention_stage3) >>> 31;
        end
    end

    // Stage 4: Compute term4 for x^4 * 1/24
    always @(posedge clk) begin
        if (!rst) begin
            term4 <= 0;
        end else if (valid_stage3) begin
            term4 <= (x_power_stage3 * x_extention_stage3 * multiplier_2) >>> 46;
        end
    end

    // Stage 4: Compute temp_stage4 with subtraction
    always @(posedge clk) begin
        if (!rst) begin
            temp_stage4 <= 0;
        end else if (valid_stage3) begin
            temp_stage4 <= temp_stage3 + term3;
        end
    end

    // Stage 4: Valid signal for stage 4
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage4 <= 0;
        end else begin
            valid_stage4 <= valid_stage3;
        end
    end

    // Stage 5: Compute x_extention_stage5
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage5 <= 0;
        end else if (valid_stage4) begin
            x_extention_stage5 <= x_extention_stage4;
        end
    end

    // Stage 5: Compute x_power_stage5 as x^5
    always @(posedge clk) begin
        if (!rst) begin
            x_power_stage5 <= 0;
        end else if (valid_stage4) begin
            x_power_stage5 <= (x_power_stage4 * x_extention_stage4) >>> 31;
        end
    end

    // Stage 5: Compute term5 for x^5 * 1/120
    always @(posedge clk) begin
        if (!rst) begin
            term5 <= 0;
        end else if (valid_stage4) begin
            term5 <= (x_power_stage4 * x_extention_stage4 * multiplier_3) >>> 46;
        end
    end

    // Stage 5: Compute temp_stage5 with addition
    always @(posedge clk) begin
        if (!rst) begin
            temp_stage5 <= 0;
        end else if (valid_stage4) begin
            temp_stage5 <= temp_stage4 + term4;
        end
    end

    // Stage 5: Valid signal for stage 5
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage5 <= 0;
        end else begin
            valid_stage5 <= valid_stage4;
        end
    end

    // Stage 6: Compute final_result with subtraction
    always @(posedge clk) begin
        if (!rst) begin
            final_result <= 0;
        end else if (valid_stage5) begin
            final_result <= temp_stage5 + term5;
        end
    end

    // Stage 6: Valid signal for stage 6
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage6 <= 0;
        end else begin
            valid_stage6 <= valid_stage5;
        end
    end

    // Output result: Truncate final_result to Q0.31 for exp_x
    always @(posedge clk) begin
        if (!rst) begin
            exp_x <= 0;
        end else if (valid_stage6) begin
            // exp_x <= { 1'd0, final_result[30:0] };
            exp_x <= (final_result[30:0] == 31'd0)? 32'h7FFFFFFF : { 1'd0, final_result[30:0] };
        end
    end

    // Output valid signal
    always @(posedge clk) begin
        if (!rst) begin
            output_valid <= 0;
        end else begin
            output_valid <= valid_stage6;
        end
    end
endmodule