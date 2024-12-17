// steps:
// 1. 先儲存所有的變數
// 2. 將input x 轉換成 1 5 31的Q format
// 3. 找出需要的shift bits
// 4. shfit x到 0.5~1 (用case判斷) 因為我總共只有1~4個bits所以很快
// 5. Xn+1 = Xn(2 - Xn * x)
// 6. 先計算出X0 = 48/17 - 32/17 * x

// Stage 0 (valid_pipeline[0]):
// 功能：計算 shift_bits，決定需要左移多少位以規範化輸入 x。
// 信號傳遞：shift_bits 存儲到 shift_bits_pipeline[2]，並通過流水線傳遞至 shift_bits_pipeline[12]。

// Stage 1 (valid_pipeline[1]):
// 功能：規範化 x，即將 x_reg 右移 shift_bits 位，得到 x_norm。
// 信號傳遞：x_norm 用於後續的倒數迭代。

// Stage 2 (valid_pipeline[2]):
// 功能：計算初始近似值 xi[0] = 48/17 - (32/17) * x_norm。
// 信號傳遞：xi[0] 存儲並用於第一輪迭代。

// Stages 3-5 (valid_pipeline[3] to valid_pipeline[5]):
// 功能：第一輪迭代計算：
//          temp_mul[0] = (xi[0] * x_norm) >> shift_amount
//          temp_sub[0] = 2 * SCALE_FACTOR - temp_mul[0]
//          xi[1] = (xi[0] * temp_sub[0]) >> FRACTIONAL_BITS
// 信號傳遞：xi[1] 存儲並用於第二輪迭代。

// Stages 6-8 (valid_pipeline[6] to valid_pipeline[8]):
// 功能：第二輪迭代計算：
//          temp_mul[1] = (xi[1] * x_norm) >> shift_amount
//          temp_sub[1] = 2 * SCALE_FACTOR - temp_mul[1]
//          xi[2] = (xi[1] * temp_sub[1]) >> FRACTIONAL_BITS
// 信號傳遞：xi[2] 存儲並用於第三輪迭代。

// Stages 9-11 (valid_pipeline[9] to valid_pipeline[11]):
// 功能：第三輪迭代計算：
//          temp_mul[2] = (xi[2] * x_norm) >> shift_amount
//          temp_sub[2] = 2 * SCALE_FACTOR - temp_mul[2]
//          xi[3] = (xi[2] * temp_sub[2]) >> FRACTIONAL_BITS
// 信號傳遞：xi[3] 存儲並用於最終的結果調整。

// Stage 12 (valid_pipeline[12]):
// 功能：調整倒數結果 reciprocal_scaled = xi[3] >> shift_bits_pipeline。
// 信號傳遞：將 reciprocal_scaled 的第 30 到 0 位 與符號位 0 拼接，形成 32 位的 reciprocal 輸出。

`timescale 1ns / 1ps
`include "params.vh"

module reciprocal_over_1(
    input wire clk,
    input wire rst,
    input wire [31:0] x,
    input wire [3:0] x_integer_bits,
    input wire input_valid,
    output reg [31:0] reciprocal,
    output reg output_valid
);

    // Constants (scaled for your fixed-point representation)
    /////////////////////////////////////////////////////
    // 1 sign bit | 5 integer bits | 31 fractional bit //
    /////////////////////////////////////////////////////
    localparam TOTAL_INTEGER_BITS = 5;
    localparam FRACTIONAL_BITS = 31;
    localparam TOTAL_BITS = 1 + TOTAL_INTEGER_BITS + FRACTIONAL_BITS;
    localparam [TOTAL_BITS-1:0] SCALE_FACTOR = 1 << FRACTIONAL_BITS;
    
    localparam [TOTAL_BITS-1:0] CONSTANT_48_OVER_17 = 37'b0_00010_1101001011010010110100101101001; // Approximation of 48/17
    localparam [TOTAL_BITS-1:0] CONSTANT_32_OVER_17 = 37'b0_00001_1110000111100001111000011110000; // Approximation of 32/17
    localparam [TOTAL_BITS-1:0] CONSTANT_2 = SCALE_FACTOR <<< 1;
    localparam [TOTAL_BITS-1:0] CONSTANT_1 = SCALE_FACTOR;

    // Internal registers
    reg [TOTAL_BITS-1:0] x_reg;                // Stores the converted input x
    reg [TOTAL_BITS-1:0] x_reg_pipeline; // x_reg passed through the pipeline
    reg [TOTAL_INTEGER_BITS-2:0] integer_part; // Integer part
    reg [2:0] shift_bits;                      // Number of bits to shift
    reg [2:0] shift_bits_pipeline [0:12];      // Shift bits passed through the pipeline
    reg [TOTAL_BITS-1:0] x_norm_pipeline[0:12]; // Normalized x passed through the pipeline
    reg [TOTAL_BITS*2-1:0] xi [0:3];           // Iteration values, including initial and 3 iterations
    reg [TOTAL_BITS*2-1:0] temp_mul [0:2];     // Intermediate multiplication results
    reg [TOTAL_BITS-1:0] temp_sub [0:2];       // Stores (2 - x_norm * xi)
    reg [13:0] valid_pipeline;                 // Validity pipeline bits
    genvar g_i;
    integer i;

    // Pipeline control
    always @(posedge clk) begin
        if (!rst) begin
            valid_pipeline <= 8'b0;
        end else begin
            valid_pipeline <= {valid_pipeline[12:0], input_valid};
        end
    end

    // Passing shift_bits through the pipeline
    always @(posedge clk) begin
        if (!rst) begin
            for (i = 0; i <= 12; i = i + 1) begin
                shift_bits_pipeline[i] <= 0;
            end
        end else begin
            for (i = 3; i <= 12; i = i + 1) begin
                shift_bits_pipeline[i] <= shift_bits_pipeline[i-1];
            end
            if (valid_pipeline[1]) begin
                shift_bits_pipeline[2] <= shift_bits;
            end
        end
    end

    // pass x_reg through the pipeline
    always @(posedge clk)begin
        if(!rst) begin
            x_reg_pipeline <= 0;
        end else  if(valid_pipeline[0])begin
            x_reg_pipeline <= x_reg;
        end
    end 

    // Store input_valid
    always @(posedge clk) begin
        if (!rst) begin
            x_reg <= 0;
        end else if (input_valid) begin
            // Convert input x to fixed-point representation
            x_reg[TOTAL_BITS-1] <= x[31]; // Sign bit

            // Integer part
            case (x_integer_bits)
                4'd0: x_reg[35:31] <= 5'b0;
                4'd1: x_reg[35:31] <= {4'b0, x[30]};
                4'd2: x_reg[35:31] <= {3'b0, x[30:29]};
                4'd3: x_reg[35:31] <= {2'b0, x[30:28]};
                4'd4: x_reg[35:31] <= {1'b0, x[30:27]};
                4'd5: x_reg[35:31] <= x[30:26];
                default: x_reg[35:31] <= 5'b0;
            endcase

            // Fractional part
            case (x_integer_bits)
                4'd0: x_reg[30:0] <= x[30:0];
                4'd1: x_reg[30:0] <= {x[29:0], 1'b0};
                4'd2: x_reg[30:0] <= {x[28:0], 2'b0};
                4'd3: x_reg[30:0] <= {x[27:0], 3'b0};
                4'd4: x_reg[30:0] <= {x[26:0], 4'b0};
                4'd5: x_reg[30:0] <= {x[25:0], 5'b0};
                default: x_reg[30:0] <= x[30:0];
            endcase
        end
    end

    // Pass x_integer_bits if necessary
    reg [3:0] x_integer_bits_reg;
    always @(posedge clk) begin
        if (!rst) begin
            x_integer_bits_reg <= 0;
        end else if (input_valid) begin
            x_integer_bits_reg <= x_integer_bits;
        end
    end

    // Assign integer_part
    always @(posedge clk) begin
        if (!rst) begin
            integer_part <= 0;
        end else if (input_valid) begin
            case (x_integer_bits)
                4'd0: integer_part <= 4'b0;
                4'd1: integer_part <= {3'b0, x[30]};
                4'd2: integer_part <= {2'b0, x[30:29]};
                4'd3: integer_part <= {1'b0, x[30:28]};
                4'd4: integer_part <= x[30:27];
                default: integer_part <= 4'b0;
            endcase
        end
    end

    // Step 2 and 3: Count leading zeros and calculate the required shift bits
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            shift_bits <= 0;
        end else if (valid_pipeline[0]) begin
            case (x_integer_bits_reg)
                4'd0: shift_bits <= 3'd0; // No integer bits, no shift required
                4'd1: begin
                    case (integer_part[0])
                        1'b1: shift_bits <= 3'd1;
                        default: shift_bits <= 3'd0;
                    endcase
                end
                4'd2: begin
                    casez (integer_part[1:0])
                        2'b1?: shift_bits <= 3'd2;
                        2'b01: shift_bits <= 3'd1;
                    endcase
                end
                4'd3: begin
                    casez (integer_part[2:0])
                        3'b1??: shift_bits <= 3'd3;
                        3'b01?: shift_bits <= 3'd2;
                        3'b001: shift_bits <= 3'd1;
                    endcase
                end
                4'd4: begin
                    casez (integer_part[3:0])
                        4'b1???: shift_bits <= 3'd4;
                        4'b01??: shift_bits <= 3'd3;
                        4'b001?: shift_bits <= 3'd2;
                        4'b0001: shift_bits <= 3'd1;
                    endcase
                end
                default: shift_bits <= 3'd0;
            endcase
        end
    end

    // Step 4: Normalize x (right shift by shift_bits)
    always @(posedge clk) begin
        if (!rst) begin
            for(i = 0; i <= 12; i = i + 1) begin
                x_norm_pipeline[i] <= 0;
            end
        end else begin
            if(valid_pipeline[1]) begin
                x_norm_pipeline[2] <= x_reg_pipeline >> shift_bits;
            end
            for(i = 3; i <= 12; i = i + 1) begin
                x_norm_pipeline[i] <= x_norm_pipeline[i-1];
            end
        end
    end

    // Step 5: Compute initial approximation X0 = 48/17 - (32/17) * x_norm
    always @(posedge clk) begin
        if (!rst) begin
            xi[0] <= 0;
        end else if (valid_pipeline[2]) begin
            xi[0] <= CONSTANT_48_OVER_17 - ((CONSTANT_32_OVER_17 * x_norm_pipeline[2]) >> 31 );
        end
    end

    // Iterative computation Xn+1 = Xn * (2 - Xn * x_norm)
    integer xi_pipeline_idx;
    generate
        for (g_i = 0; g_i < 3; g_i = g_i + 1) begin : iteration_loop
            reg [TOTAL_BITS*2-1:0] xi_pipeline [0:2];

            always @(posedge clk) begin
                if(!rst) begin
                    for(xi_pipeline_idx=0; xi_pipeline_idx<3; xi_pipeline_idx=xi_pipeline_idx+1)begin
                        xi_pipeline[xi_pipeline_idx] <= 0;
                    end
                end else begin
                    // for(xi_pipeline_idx=2; xi_pipeline_idx<3; xi_pipeline_idx=xi_pipeline_idx+1)begin
                        xi_pipeline[2] <= xi_pipeline[1];
                    // end
                    if(valid_pipeline[3 + 3 * g_i]) begin
                        xi_pipeline[1] <= xi[g_i];
                    end
                end
            end


            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    temp_mul[g_i] <= 0;
                end else if (valid_pipeline[3 + 3 * g_i]) begin
                    temp_mul[g_i] <= (xi[g_i] * x_norm_pipeline[3 + 3*g_i ]) >> 31;
                end
            end

            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    temp_sub[g_i] <= 0;
                end else if (valid_pipeline[4 + 3 * g_i]) begin
                    temp_sub[g_i] <= CONSTANT_2 - temp_mul[g_i];
                end
            end

            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    xi[g_i+1] <= 0;
                end else if (valid_pipeline[5 + 3 * g_i]) begin
                    xi[g_i+1] <= (xi_pipeline[2] * temp_sub[g_i]) >> FRACTIONAL_BITS;
                end
            end
        end
    endgenerate

    // Step 7: Adjust the reciprocal result, right shift to correct for normalization
    reg [TOTAL_BITS*2-1:0] reciprocal_scaled;
    always @(posedge clk) begin
        if (!rst) begin
            reciprocal_scaled <= 0;
        end else if (valid_pipeline[12]) begin
            reciprocal_scaled <= xi[3] >> shift_bits_pipeline[12];
        end
    end

    // Step 8: Output the result
    always @(posedge clk) begin
        if (!rst) begin
            reciprocal <= 0;
            output_valid <= 0;
        end else begin
            output_valid <= valid_pipeline[13];
            if (valid_pipeline[13]) begin
                reciprocal <= { 1'b0, reciprocal_scaled[30:0] };
            end
        end
    end
    
endmodule
