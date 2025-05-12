`timescale 1ns / 1ps
`include "params.vh"

module ADD_Element (
    input  clk,
    input  rst,
    input  input_valid,
    input  signed [INT8_SIZE-1:0] in1,
    input  signed [INT8_SIZE-1:0] in2,
    input  signed [INT32_SIZE-1:0] input1_offset,
    input  signed [INT32_SIZE-1:0] input2_offset,
    input  [INT32_SIZE-1:0] left_shift,
    input  signed [INT32_SIZE-1:0] input1_multiplier,
    input  signed [INT32_SIZE-1:0] input2_multiplier,
    input  signed [INT32_SIZE-1:0] input1_shift,
    input  signed [INT32_SIZE-1:0] input2_shift,
    input  signed [INT32_SIZE-1:0] output_multiplier,
    input  signed [INT32_SIZE-1:0] output_shift,
    input  signed [INT32_SIZE-1:0] output_offset,
    input  signed [31:0] quantized_activation_min,
    input  signed [31:0] quantized_activation_max,
    output reg signed [INT8_SIZE-1:0] out,
    output reg valid
);
    reg input_valid_reg;
    always @(posedge clk or negedge rst) begin
        if (!rst)
            input_valid_reg <= 0;
        else
            input_valid_reg <= input_valid;
    end
    //===================================================
    // Stage 0: 鎖存所有參數 (每個參數一個 always)
    //===================================================
    reg signed [INT32_SIZE-1:0] stage0_input1_offset;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input1_offset <= 0;
      else stage0_input1_offset <= input1_offset;

    reg signed [INT32_SIZE-1:0] stage0_input2_offset;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input2_offset <= 0;
      else stage0_input2_offset <= input2_offset;

    reg [INT32_SIZE-1:0] stage0_left_shift;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_left_shift <= 0;
      else stage0_left_shift <= left_shift;

    reg signed [INT32_SIZE-1:0] stage0_input1_multiplier;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input1_multiplier <= 0;
      else stage0_input1_multiplier <= input1_multiplier;

    reg signed [INT32_SIZE-1:0] stage0_input2_multiplier;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input2_multiplier <= 0;
      else stage0_input2_multiplier <= input2_multiplier;

    reg signed [INT32_SIZE-1:0] stage0_input1_shift;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input1_shift <= 0;
      else stage0_input1_shift <= input1_shift;

    reg signed [INT32_SIZE-1:0] stage0_input2_shift;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_input2_shift <= 0;
      else stage0_input2_shift <= input2_shift;

    reg signed [INT32_SIZE-1:0] stage0_output_multiplier;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_multiplier <= 0;
      else stage0_output_multiplier <= output_multiplier;

    reg signed [INT32_SIZE-1:0] stage0_output_shift;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_shift <= 0;
      else stage0_output_shift <= output_shift;

    reg signed [INT32_SIZE-1:0] stage0_output_offset;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_output_offset <= 0;
      else stage0_output_offset <= output_offset;

    reg signed [31:0] stage0_quantized_activation_min;
    reg signed [31:0] stage_quantized_activation_min[0:5];
    integer i;
    always @(posedge clk or negedge rst)
      if (!rst) stage0_quantized_activation_min <= 0;
      else stage0_quantized_activation_min <= quantized_activation_min;
    
    always @(posedge clk or negedge rst) begin
      if(!rst) begin
        for(i = 0; i < 6; i = i + 1) begin
          stage_quantized_activation_min[i] <= 0;
        end
      end else begin
        stage_quantized_activation_min[0] <= stage0_quantized_activation_min;
        stage_quantized_activation_min[1] <= stage_quantized_activation_min[0];
        stage_quantized_activation_min[2] <= stage_quantized_activation_min[1];
        stage_quantized_activation_min[3] <= stage_quantized_activation_min[2];
        stage_quantized_activation_min[4] <= stage_quantized_activation_min[3];
        stage_quantized_activation_min[5] <= stage_quantized_activation_min[4];
      end
    end

    reg signed [31:0] stage0_quantized_activation_max;
    reg signed [31:0] stage_quantized_activation_max[0:5];
    always @(posedge clk or negedge rst)
      if (!rst) stage0_quantized_activation_max <= 0;
      else stage0_quantized_activation_max <= quantized_activation_max;

    always @(posedge clk or negedge rst) begin
      if(!rst) begin
        for(i = 0; i < 6; i = i + 1) begin
          stage_quantized_activation_max[i] <= 0;
        end
      end else begin
        stage_quantized_activation_max[0] <= stage0_quantized_activation_max;
        stage_quantized_activation_max[1] <= stage_quantized_activation_max[0];
        stage_quantized_activation_max[2] <= stage_quantized_activation_max[1];
        stage_quantized_activation_max[3] <= stage_quantized_activation_max[2];
        stage_quantized_activation_max[4] <= stage_quantized_activation_max[3];
        stage_quantized_activation_max[5] <= stage_quantized_activation_max[4];
      end
    end
    reg [INT8_SIZE-1:0] in1_reg, in2_reg;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            in1_reg <= 0;
            in2_reg <= 0;
        end else begin
            in1_reg <= in1;
            in2_reg <= in2;
        end
    end
    //===================================================
    // Stage 1_2: 合併 Offset 校正與左移放大
    // 計算: stage1_2 = (in + offset) * (1 << left_shift)
    //===================================================
    reg signed [INT32_SIZE-1:0] stage1_2_in1;
    reg signed [INT32_SIZE-1:0] stage1_2_in2;
    reg stage1_2_valid;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            stage1_2_in1 <= 0;
            stage1_2_valid <= 0;
        end else begin
            stage1_2_in1 <= ($signed(in1_reg) + stage0_input1_offset) * (1 << stage0_left_shift);
            stage1_2_valid <= input_valid_reg;
        end
    end

    always @(posedge clk or negedge rst) begin
        if (!rst)
            stage1_2_in2 <= 0;
        else
            stage1_2_in2 <= ($signed(in2_reg) + stage0_input2_offset) * (1 << stage0_left_shift);
    end

    //===================================================
    // Stage 3: 輸入側量化縮放 (Requant)
    //===================================================
    wire valid_mul1, valid_mul2;
    wire signed [INT32_SIZE-1:0] stage3_scaled1;
    wire signed [INT32_SIZE-1:0] stage3_scaled2;

    MultiplyByQuantizedMultiplierSmallerThanOneExp mqm1 (
        .clk(clk),
        .rst(rst),
        .x(stage1_2_in1),
        .quantized_multiplier(stage0_input1_multiplier),
        .shift(stage0_input1_shift),  // 直接將 shift 取負
        .input_valid(stage1_2_valid),
        .output_valid(valid_mul1),
        .x_mul_by_quantized_multiplier(stage3_scaled1)
    );
    MultiplyByQuantizedMultiplierSmallerThanOneExp mqm2 (
        .clk(clk),
        .rst(rst),
        .x(stage1_2_in2),
        .quantized_multiplier(stage0_input2_multiplier),
        .shift(stage0_input2_shift),
        .input_valid(stage1_2_valid),
        .output_valid(valid_mul2),
        .x_mul_by_quantized_multiplier(stage3_scaled2)
    );
    
    //===================================================
    // Stage 4: 元素加法
    //===================================================
    reg signed [INT32_SIZE-1:0] stage4_sum;
    always @(posedge clk or negedge rst)
      if (!rst) stage4_sum <= 0;
      else stage4_sum <= stage3_scaled1 + stage3_scaled2;

    reg stage4_valid;
    always @(posedge clk or negedge rst)
      if (!rst) stage4_valid <= 0;
      else if(valid_mul1 & valid_mul2) stage4_valid <= 1;
      else stage4_valid <= 0;
      // else stage4_valid <= valid_mul1 & valid_mul2;

    //===================================================
    // Stage 5: 第二次 Requant 化
    // 計算: stage5_requant = MultiplyByQuantizedMultiplierSmallerThanOneExp(stage4_sum, output_multiplier, -output_shift)
    //===================================================
    wire valid_requant;
    wire signed [INT32_SIZE-1:0] stage5_requant;
    MultiplyByQuantizedMultiplierSmallerThanOneExp mqm_final (
        .clk(clk),
        .rst(rst),
        .x(stage4_sum),
        .quantized_multiplier(stage0_output_multiplier),
        .shift(stage0_output_shift),
        .input_valid(stage4_valid),
        .output_valid(valid_requant),
        .x_mul_by_quantized_multiplier(stage5_requant)
    );

    //===================================================
    // Stage 6: 加上 output_offset 與 Clamping
    // 計算: stage6 = clamp(stage5_requant + output_offset, quantized_activation_min, quantized_activation_max)
    //===================================================
    reg signed [INT32_SIZE-1:0] stage6_out;
    reg stage6_valid;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            stage6_out <= 0;
            stage6_valid <= 0;
        end else begin
            // 先加上 output_offset
            stage6_out <= stage5_requant + stage0_output_offset;
            stage6_valid <= valid_requant;
        end
    end

    reg signed [INT32_SIZE-1:0] stage6_clamped;
    reg stage6_clamp_valid;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            stage6_clamped <= 0;
            stage6_clamp_valid <= 0;
        end else begin
            if (stage6_out < stage_quantized_activation_min[5])
                stage6_clamped <= stage_quantized_activation_min[5];
            else if (stage6_out > stage_quantized_activation_max[5])
                stage6_clamped <= stage_quantized_activation_max[5];
            else
                stage6_clamped <= stage6_out;
            stage6_clamp_valid <= stage6_valid;
        end
    end

    //===================================================
    // Stage 7: 最終轉換為 INT8 輸出
    //===================================================
    always @(posedge clk or negedge rst) begin
        if (!rst)
            out <= 0;
        else
            out <= stage6_clamped[INT8_SIZE-1:0];
    end

    always @(posedge clk or negedge rst) begin
        if (!rst)
            valid <= 0;
        else
            valid <= stage6_clamp_valid;
    end

    // always @(posedge clk)begin
    //   if(valid_mul2) $display("stage3_scaled1 = %d, stage3_scaled2 = %d", stage3_scaled1, stage3_scaled2);
    //   if(stage1_2_valid) $display("stage1_2_in1 = %d, stage1_2_in2 = %d", stage1_2_in1, stage1_2_in2);
    //   if(stage6_valid) $display("stage6_out = %d", stage6_out);
    // end
endmodule
