// logistic(FixedPoint4::FromRaw(input_in_q4)).raw()

// // Returns logistic(x) = 1 / (1 + exp(-x)) for x > 0.
// template <typename tRawType, int tIntegerBits>
// FixedPoint<tRawType, 0> logistic_on_positive_values(
//     FixedPoint<tRawType, tIntegerBits> a) {
//   return one_over_one_plus_x_for_x_in_0_1(exp_on_negative_values(-a));
// }
// exp_on_negative_values -> exp(-x)
// one_over_one_plus_x_for_x_in_0_1 -> 1 / (1 + x)
// MUL -> use DW_mult_pipe to erase timing violation
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
    integer i;
    // Pipeline registers
    reg signed [43:0] x_extention_stage1, x_extention_stage2, x_extention_stage3, x_extention_stage4, x_extention_stage5;
    reg signed [87:0] x_power_stage2, x_power_stage3, x_power_stage4, x_power_stage5;
    reg signed [87:0] term1, term2, term3, term4, term5;
    reg signed [87:0] temp_stage1, temp_stage2, temp_stage3, temp_stage4, temp_stage5;
    reg signed [87:0] final_result;

    // Valid signal propagation through the pipeline
    reg valid_stage1, valid_stage2, valid_stage3, valid_stage4, valid_stage5, valid_stage6, valid_stage7;

    // DW mul enable vector
    wire [MUL_DEPTH-1:0] stage2a_dw_en, stage3a_dw_en, stage4a_dw_en, stage5a_dw_en;
    wire s2a_dw_en, s3a_dw_en, s4a_dw_en, s5a_dw_en;
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
    // Stage 2a: new stage for x^2
    reg signed [87:0] x_sq_stage2a, temp_stage2a, term2a;
    reg signed [43:0] x_extention_stage2a;
    reg valid_stage2a;
    always @(posedge clk )begin
        if(!rst) begin
            valid_stage2a <= 0;
        end else begin
            valid_stage2a <= valid_stage1;
        end
    end

    always @(posedge clk )begin
        if(!rst) begin
            temp_stage2a <= 0;
            term2a <= 0;
            x_extention_stage2a <= 0;
            // x_sq_stage2a <= 0;
        end else if(valid_stage1) begin
            temp_stage2a <= temp_stage1;
            term2a <= term1;
            x_extention_stage2a <= x_extention_stage1;
            // x_sq_stage2a <= x_extention_stage1 * x_extention_stage1;
        end
    end

    DW_mult_pipe_inst DW_mult_pipe_inst_1 
    (
        .inst_clk(clk),
        .inst_rst_n(rst),
        .inst_en(s2a_dw_en),
        .inst_tc(1'b1),
        .inst_a(x_extention_stage1),
        .inst_b(x_extention_stage1),
        .product_inst(x_sq_stage2a)
    );

    reg signed [43:0] ext2_d[0:MUL_DEPTH-1];
    reg signed [87:0] term2_d[0:MUL_DEPTH-1];
    reg signed [87:0] tmp2_d[0:MUL_DEPTH-1];
    reg               v2_d[0:MUL_DEPTH-1];
    wire any_valid_2b;
    genvar j;
    generate
        for (j=0; j<MUL_DEPTH; j=j+1) begin
            assign stage2a_dw_en[j] = v2_d[j];
        end
    endgenerate
    assign any_valid_2b = |stage2a_dw_en;
    assign s2a_dw_en = valid_stage1 | any_valid_2b;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for(i = 0; i<MUL_DEPTH; i=i+1) begin
                ext2_d[i]  <= 0;
                term2_d[i] <= 0;
                tmp2_d[i]  <= 0;
                v2_d[i]    <= 0;
            end
        end else begin
            for(i = 0; i<MUL_DEPTH-1; i=i+1) begin
                ext2_d[i+1]  <= ext2_d[i];
                term2_d[i+1] <= term2_d[i];
                tmp2_d[i+1]  <= tmp2_d[i];
                v2_d[i+1]    <= v2_d[i];
            end
            ext2_d[0]  <= x_extention_stage1;
            term2_d[0] <= term1;
            tmp2_d[0]  <= temp_stage1;
            v2_d[0] <= valid_stage1;
        end
    end
    // always @(posedge clk )begin
    //     if(!rst) begin
    //         term2a <= 0;
    //     end else if(valid_stage1) begin
    //         term2a <= term1;
    //     end
    // end

    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_extention_stage2a <= 0;
    //     end else if(valid_stage1) begin
    //         x_extention_stage2a <= x_extention_stage1;
    //     end
    // end

    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_sq_stage2a <= 0;
    //     end else if(valid_stage1) begin
    //         x_sq_stage2a <= x_extention_stage1 * x_extention_stage1;
    //     end
    // end



    // Stage 2: Compute x_extention_stage2
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage2 <= 0;
            x_power_stage2 <= 0;
            term2 <= 0;
            temp_stage2 <= 0;
        end else if (v2_d[MUL_DEPTH-2]) begin
            x_extention_stage2 <= ext2_d[MUL_DEPTH-2];
            x_power_stage2     <= x_sq_stage2a >>> 31;
            term2              <= (x_sq_stage2a * multiplier_0) >>> 46;
            temp_stage2        <= tmp2_d[MUL_DEPTH-2] + term2_d[MUL_DEPTH-2];
        end
    end

    // Stage 2: Compute x_power_stage2 as x^2
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         x_power_stage2 <= 0;
    //     end else if (valid_stage2a) begin
    //         x_power_stage2 <= x_sq_stage2a >>> 31;
    //     end
    // end

    // Stage 2: Compute term2 for x^2 * 1/2
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         term2 <= 0;
    //     end else if (valid_stage2a) begin
    //         term2 <= (x_sq_stage2a * multiplier_0) >>> 46;
    //     end
    // end

    // Stage 2: Compute temp_stage2 with subtraction
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         temp_stage2 <= 0;
    //     end else if (valid_stage2a) begin
    //         temp_stage2 <= temp_stage2a + term2a;
    //     end
    // end

    // Stage 2: Valid signal for stage 2
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage2 <= 0;
        end else begin
            valid_stage2 <= v2_d[MUL_DEPTH-2];
        end
    end

    // Stage 3a: new stage for x^3
    reg signed [87:0] x_sq_stage3a, temp_stage3a, term3a;
    reg signed [43:0] x_extention_stage3a;
    reg valid_stage3a;
    always @(posedge clk )begin
        if(!rst) begin
            valid_stage3a <= 0;
        end else begin
            valid_stage3a <= valid_stage2;
        end
    end
    always @(posedge clk )begin
        if(!rst) begin
            temp_stage3a <= 0;
            term3a <= 0;
            x_extention_stage3a <= 0;
            // x_sq_stage3a <= 0;
        end else if(valid_stage2) begin
            temp_stage3a <= temp_stage2;
            term3a <= term2;
            x_extention_stage3a <= x_extention_stage2;
            // x_sq_stage3a <= x_power_stage2 * x_extention_stage2;
        end
    end

    DW_mult_pipe_inst_88_44 DW_mult_pipe_inst_2
    (
        .inst_clk(clk),
        .inst_rst_n(rst),
        .inst_en(s3a_dw_en),
        .inst_tc(1'b1),
        .inst_a(x_power_stage2),
        .inst_b(x_extention_stage2),
        .product_inst(x_sq_stage3a)
    );

    reg signed [43:0] ext3_d[0:MUL_DEPTH-1];
    reg signed [87:0] term3_d[0:MUL_DEPTH-1];
    reg signed [87:0] tmp3_d[0:MUL_DEPTH-1];
    reg               v3_d[0:MUL_DEPTH-1];
    wire any_valid_3b;
    generate
        for(j=0; j<MUL_DEPTH; j=j+1) begin
            assign stage3a_dw_en[j] = v3_d[j];
        end
    endgenerate
    assign any_valid_3b = |stage3a_dw_en;
    assign s3a_dw_en = valid_stage2 | any_valid_3b;

    always @(posedge clk) begin
        if (!rst) begin
            for(i = 0; i<MUL_DEPTH; i=i+1) begin
                ext3_d[i]  <= 0;
                term3_d[i] <= 0;
                tmp3_d[i]  <= 0;
                v3_d[i]    <= 0;
            end
        end else begin
            for(i = 0; i<MUL_DEPTH-1; i=i+1) begin
                ext3_d[i+1]  <= ext3_d[i];
                term3_d[i+1] <= term3_d[i];
                tmp3_d[i+1]  <= tmp3_d[i];
                v3_d[i+1]    <= v3_d[i];
            end
            ext3_d[0]  <= x_extention_stage2;
            term3_d[0] <= term2;
            tmp3_d[0]  <= temp_stage2;
            v3_d[0] <= valid_stage2;
        end
    end

    // always @(posedge clk )begin
    //     if(!rst) begin
    //         term3a <= 0;
    //     end else if(valid_stage2) begin
    //         term3a <= term2;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_extention_stage3a <= 0;
    //     end else if(valid_stage2) begin
    //         x_extention_stage3a <= x_extention_stage2;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_sq_stage3a <= 0;
    //     end else if(valid_stage2) begin
    //         x_sq_stage3a <= x_power_stage2 * x_extention_stage2;
    //     end
    // end

    // Stage 3: Compute x_extention_stage3
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage3 <= 0;
            x_power_stage3 <= 0;
            term3 <= 0;
            temp_stage3 <= 0;
        end else if (v3_d[MUL_DEPTH-2]) begin
            x_extention_stage3 <= ext3_d[MUL_DEPTH-2];
            x_power_stage3 <= x_sq_stage3a >>> 31;
            term3        <= (x_sq_stage3a * multiplier_1) >>> 46;
            temp_stage3  <= (tmp3_d[MUL_DEPTH-2] + term3_d[MUL_DEPTH-2]);
        end
    end

    // Stage 3: Compute x_power_stage3 as x^3
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         x_power_stage3 <= 0;
    //     end else if (valid_stage3a) begin
    //         x_power_stage3 <=  x_sq_stage3a >>> 31;
    //     end
    // end

    // Stage 3: Compute term3 for x^3 * 1/6
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         term3 <= 0;
    //     end else if (valid_stage3a) begin
    //         term3 <= (x_sq_stage3a * multiplier_1) >>> 46;
    //     end
    // end

    // Stage 3: Compute temp_stage3 with addition
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         temp_stage3 <= 0;
    //     end else if (valid_stage2) begin
    //         temp_stage3 <= temp_stage3a + term3a;
    //     end
    // end

    // Stage 3: Valid signal for stage 3
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage3 <= 0;
        end else begin
            valid_stage3 <= v3_d[MUL_DEPTH-2];
        end
    end

    // Stage 4a: new stage for x^4
    reg signed [87:0] x_sq_stage4a, temp_stage4a, term4a;
    reg signed [43:0] x_extention_stage4a;
    reg valid_stage4a;
    always @(posedge clk )begin
        if(!rst) begin
            valid_stage4a <= 0;
        end else begin
            valid_stage4a <= valid_stage3;
        end
    end
    always @(posedge clk )begin
        if(!rst) begin
            temp_stage4a <= 0;
            term4a <= 0;
            x_extention_stage4a <= 0;
            // x_sq_stage4a <= 0;
        end else if(valid_stage3) begin
            temp_stage4a <= temp_stage3;
            term4a <= term3;
            x_extention_stage4a <= x_extention_stage3;
            // x_sq_stage4a <= x_power_stage3 * x_extention_stage3;
        end
    end

    DW_mult_pipe_inst_88_44 DW_mult_pipe_inst_4
    (
        .inst_clk(clk),
        .inst_rst_n(rst),
        .inst_en(s4a_dw_en),
        .inst_tc(1'b1),
        .inst_a(x_power_stage3),
        .inst_b(x_extention_stage3),
        .product_inst(x_sq_stage4a)
    );

    // 2-cycle registers for stage4
    reg signed [43:0] ext4_d[0:MUL_DEPTH-1];
    reg signed [87:0] term4_d[0:MUL_DEPTH-1];
    reg signed [87:0] tmp4_d[0:MUL_DEPTH-1];
    reg               v4_d[0:MUL_DEPTH-1];
    wire any_valid_4b;
    generate
        for(j=0; j<MUL_DEPTH; j=j+1) begin
            assign stage4a_dw_en[j] = v4_d[j];
        end
    endgenerate
    assign any_valid_4b = |stage4a_dw_en;
    assign s4a_dw_en = valid_stage3 | any_valid_4b;

    always @(posedge clk) begin
        if (!rst) begin
            for(i = 0; i<MUL_DEPTH; i=i+1) begin
                ext4_d[i]  <= 0;
                term4_d[i] <= 0;
                tmp4_d[i]  <= 0;
                v4_d[i]    <= 0;
            end
        end else begin
            for(i = 0; i<MUL_DEPTH-1; i=i+1) begin
                ext4_d[i+1]  <= ext4_d[i];
                term4_d[i+1] <= term4_d[i];
                tmp4_d[i+1]  <= tmp4_d[i];
                v4_d[i+1]    <= v4_d[i];
            end
            ext4_d[0]  <= x_extention_stage3;
            term4_d[0] <= term3;
            tmp4_d[0]  <= temp_stage3;
            v4_d[0] <= valid_stage3;
        end
    end

    // always @(posedge clk )begin
    //     if(!rst) begin
    //         term4a <= 0;
    //     end else if(valid_stage3) begin
    //         term4a <= term3;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_extention_stage4a <= 0;
    //     end else if(valid_stage3) begin
    //         x_extention_stage4a <= x_extention_stage3;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_sq_stage4a <= 0;
    //     end else if(valid_stage3) begin
    //         x_sq_stage4a <= x_power_stage3 * x_extention_stage3;
    //     end
    // end

    // Stage 4: Compute x_extention_stage4
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage4 <= 0;
            x_power_stage4 <= 0;
            term4 <= 0;
            temp_stage4 <= 0;
        end else if (v4_d[MUL_DEPTH-2]) begin
            x_extention_stage4 <= ext4_d[MUL_DEPTH-2];
            x_power_stage4     <= x_sq_stage4a >>> 31;
            term4              <= (x_sq_stage4a * multiplier_2) >>> 46;
            temp_stage4        <= tmp4_d[MUL_DEPTH-2] + term4_d[MUL_DEPTH-2];
        end
    end

    // Stage 4: Compute x_power_stage4 as x^4
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         x_power_stage4 <= 0;
    //     end else if (valid_stage4a) begin
    //         x_power_stage4 <= x_sq_stage4a >>> 31;
    //     end
    // end

    // Stage 4: Compute term4 for x^4 * 1/24
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         term4 <= 0;
    //     end else if (valid_stage4a) begin
    //         term4 <= (x_sq_stage4a * multiplier_2) >>> 46;
    //     end
    // end

    // Stage 4: Compute temp_stage4 with subtraction
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         temp_stage4 <= 0;
    //     end else if (valid_stage4a) begin
    //         temp_stage4 <= temp_stage4a + term4a;
    //     end
    // end

    // Stage 4: Valid signal for stage 4
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage4 <= 0;
        end else begin
            valid_stage4 <= v4_d[MUL_DEPTH-2];
        end
    end

    // Stage 5a: new stage for x^5
    reg signed [87:0] x_sq_stage5a, temp_stage5a, term5a;
    reg signed [43:0] x_extention_stage5a;
    reg valid_stage5a;
    always @(posedge clk )begin
        if(!rst) begin
            valid_stage5a <= 0;
        end else begin
            valid_stage5a <= valid_stage4;
        end
    end
    always @(posedge clk )begin
        if(!rst) begin
            temp_stage5a <= 0;
            term5a <= 0;
            x_extention_stage5a <= 0;
            // x_sq_stage5a <= 0;
        end else if(valid_stage4) begin
            temp_stage5a <= temp_stage4;
            term5a <= term4;
            x_extention_stage5a <= x_extention_stage4;
            // x_sq_stage5a <= x_power_stage4 * x_extention_stage4;
        end
    end

    DW_mult_pipe_inst_88_44 DW_mult_pipe_inst_5
    (
        .inst_clk(clk),
        .inst_rst_n(rst),
        .inst_en(s5a_dw_en),
        .inst_tc(1'b1),
        .inst_a(x_power_stage4),
        .inst_b(x_extention_stage4),
        .product_inst(x_sq_stage5a)
    );

    // 2-cycle registers for stage5
    reg signed [43:0] ext5_d[0:MUL_DEPTH-1];
    reg signed [87:0] term5_d[0:MUL_DEPTH-1];
    reg signed [87:0] tmp5_d[0:MUL_DEPTH-1];
    reg               v5_d[0:MUL_DEPTH-1];
    wire any_valid_5b;
    generate
        for(j=0; j<MUL_DEPTH; j=j+1) begin
            assign stage5a_dw_en[j] = v5_d[j];
        end
    endgenerate
    assign any_valid_5b = |stage5a_dw_en;
    assign s5a_dw_en = valid_stage4 | any_valid_5b;

    always @(posedge clk) begin
        if (!rst) begin
            for(i = 0; i<MUL_DEPTH; i=i+1) begin
                ext5_d[i]  <= 0;
                term5_d[i] <= 0;
                tmp5_d[i]  <= 0;
                v5_d[i]    <= 0;
            end
        end else begin
            for(i = 0; i<MUL_DEPTH-1; i=i+1) begin
                ext5_d[i+1]  <= ext5_d[i];
                term5_d[i+1] <= term5_d[i];
                tmp5_d[i+1]  <= tmp5_d[i];
                v5_d[i+1]    <= v5_d[i];
            end
            ext5_d[0]  <= x_extention_stage4;
            term5_d[0] <= term4;
            tmp5_d[0]  <= temp_stage4;
            v5_d[0] <= valid_stage4;
        end
    end

    // always @(posedge clk )begin
    //     if(!rst) begin
    //         term5a <= 0;
    //     end else if(valid_stage4) begin
    //         term5a <= term4;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_extention_stage5a <= 0;
    //     end else if(valid_stage4) begin
    //         x_extention_stage5a <= x_extention_stage4;
    //     end
    // end
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         x_sq_stage5a <= 0;
    //     end else if(valid_stage4) begin
    //         x_sq_stage5a <= x_power_stage4 * x_extention_stage4;
    //     end
    // end

    // Stage 5: Compute x_extention_stage5
    always @(posedge clk) begin
        if (!rst) begin
            x_extention_stage5 <= 0;
            x_power_stage5 <= 0;
            term5 <= 0;
            temp_stage5 <= 0;
        end else if (v5_d[MUL_DEPTH-2]) begin
            x_extention_stage5 <= ext5_d[MUL_DEPTH-2];
            x_power_stage5     <= x_sq_stage5a >>> 31;
            term5              <= (x_sq_stage5a * multiplier_3) >>> 46;
            temp_stage5        <= tmp5_d[MUL_DEPTH-2] + term5_d[MUL_DEPTH-2];
        end
    end

    // Stage 5: Compute x_power_stage5 as x^5
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         x_power_stage5 <= 0;
    //     end else if (valid_stage5a) begin
    //         x_power_stage5 <= x_sq_stage5a >>> 31;
    //     end
    // end

    // Stage 5: Compute term5 for x^5 * 1/120
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         term5 <= 0;
    //     end else if (valid_stage5a) begin
    //         term5 <= (x_sq_stage5a * multiplier_3) >>> 46;
    //     end
    // end

    // Stage 5: Compute temp_stage5 with addition
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         temp_stage5 <= 0;
    //     end else if (valid_stage5a) begin
    //         temp_stage5 <= temp_stage5a + term5a;
    //     end
    // end

    // Stage 5: Valid signal for stage 5
    always @(posedge clk) begin
        if (!rst) begin
            valid_stage5 <= 0;
        end else begin
            valid_stage5 <= v5_d[MUL_DEPTH-2];
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

module DW_mult_pipe_inst(inst_clk, inst_rst_n, inst_en, inst_tc, inst_a,
                         inst_b, product_inst );
  parameter inst_a_width = 44;
  parameter inst_b_width = 44;
  parameter inst_num_stages = MUL_DEPTH;
  parameter inst_stall_mode = 1;
  parameter inst_rst_mode = 1;
  parameter inst_op_iso_mode = 0;

  input [inst_a_width-1 : 0] inst_a;
  input [inst_b_width-1 : 0] inst_b;
  input inst_tc;
  input inst_clk;
  input inst_en;
  input inst_rst_n;
  output [inst_a_width+inst_b_width-1 : 0] product_inst;
  // Instance of DW_mult_pipe
  DW_mult_pipe #(inst_a_width, inst_b_width, inst_num_stages,
                 inst_stall_mode, inst_rst_mode, inst_op_iso_mode) 
    U1 (.clk(inst_clk),   .rst_n(inst_rst_n),   .en(inst_en),
        .tc(inst_tc),   .a(inst_a),   .b(inst_b), 
        .product(product_inst) );
endmodule

module DW_mult_pipe_inst_88_44(inst_clk, inst_rst_n, inst_en, inst_tc, inst_a,
                         inst_b, product_inst );
  parameter inst_a_width = 88;
  parameter inst_b_width = 44;
  parameter inst_num_stages = MUL_DEPTH;
  parameter inst_stall_mode = 1;
  parameter inst_rst_mode = 1;
  parameter inst_op_iso_mode = 0;

  input [inst_a_width-1 : 0] inst_a;
  input [inst_b_width-1 : 0] inst_b;
  input inst_tc;
  input inst_clk;
  input inst_en;
  input inst_rst_n;
  output [87 : 0] product_inst;
  wire [inst_a_width + inst_b_width - 1 : 0] full_product;
  assign product_inst = full_product[87:0];
  // Instance of DW_mult_pipe
  DW_mult_pipe #(inst_a_width, inst_b_width, inst_num_stages,
                 inst_stall_mode, inst_rst_mode, inst_op_iso_mode) 
    U1 (.clk(inst_clk),   .rst_n(inst_rst_n),   .en(inst_en),
        .tc(inst_tc),   .a(inst_a),   .b(inst_b), 
        .product(full_product) );
endmodule