`timescale 1ns / 1ps

module exp_CORDIC #(
    parameter ITERATIONS = 16  // 此處定義唯一移位次數（不含重複迭代），可根據需要提高以獲得更高精度
)(
    input  wire clk,
    input  wire rst,               // 同步／非同步低有效重置
    input  wire signed [31:0] x,   // 輸入值，以 Q4.27 格式表示（此處允許負數）
    input  wire [3:0] integer_bits, // 整數部分位數（本程式碼中未使用，可作範圍控制用）
    input  wire input_valid,       // 輸入有效訊號
    output reg [31:0] exp_x,       // 輸出 exp(x)，以 Q0.31 格式表示
    output reg output_valid        // 輸出有效訊號
);

    //-------------------------------------------------------------------------
    // 定義一個帶四捨五入的右移 function（對有符號數）
    // 當 shift > 0 時：如果數值為正則加上 1<<(shift-1)；負則減去 1<<(shift-1) 再右移。
    function automatic signed [31:0] round_shr;
        input signed [31:0] in;
        input [4:0] sh;
        begin
            if (sh == 0)
                round_shr = in;
            else if (in[31] == 0)  // 正數
                round_shr = (in + (1 << (sh - 1))) >>> sh;
            else                   // 負數
                round_shr = (in - (1 << (sh - 1))) >>> sh;
        end
    endfunction

    //-------------------------------------------------------------------------
    // 為了保證超雙曲收斂，第 4 與第 13 次迭代需要重複
    // 總迭代次數 = ITERATIONS + 2
    localparam TOTAL_ITER = ITERATIONS + 2;

    //-------------------------------------------------------------------------
    // ARCTANH_TABLE：針對移位 1~16 的 arctanh(2^-i) 值（Q4.27 格式）
    localparam signed [31:0] ARCTANH_TABLE [0:15] = '{
        32'h0460E515, // shift=1, arctanh(2^-1) ≈ 0.549306
        32'h020A3D4C, // shift=2, arctanh(2^-2) ≈ 0.255413
        32'h01013F74, // shift=3, arctanh(2^-3) ≈ 0.125657
        32'h00801234, // shift=4, arctanh(2^-4) ≈ 0.0625816
        32'h00400AC2, // shift=5, arctanh(2^-5) ≈ 0.0312602
        32'h00200501, // shift=6, arctanh(2^-6) ≈ 0.0156263
        32'h00100278, // shift=7, arctanh(2^-7) ≈ 0.0078127
        32'h00080136, // shift=8, arctanh(2^-8) ≈ 0.0039063
        32'h0004009C, // shift=9, arctanh(2^-9) ≈ 0.0019531
        32'h0002004A, // shift=10, arctanh(2^-10) ≈ 0.0009766
        32'h00010025, // shift=11, arctanh(2^-11) ≈ 0.0004883
        32'h00008013, // shift=12, arctanh(2^-12) ≈ 0.0002441
        32'h00004009, // shift=13, arctanh(2^-13) ≈ 0.0001221
        32'h00002004, // shift=14, arctanh(2^-14) ≈ 0.0000610
        32'h00001002, // shift=15, arctanh(2^-15) ≈ 0.0000305
        32'h00000801  // shift=16, arctanh(2^-16) ≈ 0.00001526
    };

    //-------------------------------------------------------------------------
    // 為計算 exp(x) = cosh(x) + sinh(x)（正輸入）或 exp(x)=cosh(|x|)-sinh(|x|)（負輸入）
    // 修改初始向量設定為 (1/K, 0) 而非 (1/K, 1/K)
    // 其中 K 為超雙曲 CORDIC 的增益，1/K ≈ 0.828
    // 以 Q4.27 表示：0.828 * 2^27 ≈ 111084538
    localparam signed [31:0] SCALE_FACTOR = 32'd115415000; // 初始向量 X0 (Q4.27)
    // 補償因子 K，在 Q4.27 表示約 1.2075 * 2^27 ≈ 161910000
    localparam signed [31:0] GAIN = 32'd156190000; // Q4.27

    //-------------------------------------------------------------------------
    // 內部寄存器 (皆以 Q4.27 格式表示)
    reg signed [31:0] x_reg, y_reg, z_reg;
    reg [5:0] iter_count;       // 迭代計數器
    reg running;                // 運算中指示旗標
    reg negative_flag;          // 標記輸入是否為負

    //-------------------------------------------------------------------------
    // 根據迭代計數器決定實際移位數 shift_value
    reg [4:0] shift_value;
    always @(*) begin
        case(iter_count)
            0:  shift_value = 1;
            1:  shift_value = 2;
            2:  shift_value = 3;
            3:  shift_value = 4;
            4:  shift_value = 4;  // 重複迭代：移位數同 4
            5:  shift_value = 5;
            6:  shift_value = 6;
            7:  shift_value = 7;
            8:  shift_value = 8;
            9:  shift_value = 9;
            10: shift_value = 10;
            11: shift_value = 11;
            12: shift_value = 12;
            13: shift_value = 13;
            14: shift_value = 13; // 重複迭代：移位數同 13
            15: shift_value = 14;
            16: shift_value = 15;
            17: shift_value = 16;
            default: shift_value = 0;
        endcase
    end

    //-------------------------------------------------------------------------
    // 暫存新狀態的計算（每次迭代使用上個時脈的 x_reg、y_reg、z_reg）
    // 修正重點：在每次迭代中，對移位操作加上四捨五入處理；
    //           且在重複迭代（iter_count==4 或 iter_count==14）時，僅更新 x 與 y，而跳過 z 的更新
    reg signed [31:0] x_next, y_next, z_next;
    always @(*) begin
        if (z_reg[31] == 0) begin // z_reg >= 0, d = +1
            x_next = x_reg + round_shr(y_reg, shift_value);
            y_next = y_reg + round_shr(x_reg, shift_value);
            if ((iter_count == 4) || (iter_count == 14))
                z_next = z_reg;  // 重複迭代時，不更新 z
            else
                z_next = z_reg - ARCTANH_TABLE[shift_value - 1];
        end else begin // z_reg < 0, d = -1
            x_next = x_reg - round_shr(y_reg, shift_value);
            y_next = y_reg - round_shr(x_reg, shift_value);
            if ((iter_count == 4) || (iter_count == 14))
                z_next = z_reg;  // 重複迭代時，不更新 z
            else
                z_next = z_reg + ARCTANH_TABLE[shift_value - 1];
        end
    end

    //-------------------------------------------------------------------------
    // 最終結果組合：
    // 經過迭代後，x_reg 與 y_reg 分別約為 cosh(|x|)/K 與 sinh(|x|)/K (Q4.27)
    // 對正輸入：exp(x)=K*(cosh(x)+sinh(x))
    // 對負輸入：exp(x)=K*(cosh(|x|)-sinh(|x|))
    // 乘上 K 後，數值為 Q8.54，再右移 23 位轉換成 Q0.31 (因 54-23=31)
    wire signed [62:0] tmp_result;
    assign tmp_result = (negative_flag ? (x_reg - y_reg) : (x_reg + y_reg)) * GAIN;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            x_reg         <= 0;
            y_reg         <= 0;
            z_reg         <= 0;
            iter_count    <= 0;
            running       <= 0;
            exp_x         <= 0;
            output_valid  <= 0;
            negative_flag <= 0;
        end else begin
            if (input_valid && !running) begin
                // 有新輸入時啟動運算
                if (x[31] == 1) begin
                    z_reg         <= -x;  // 負數取絕對值
                    negative_flag <= 1;
                end else begin
                    z_reg         <= x;
                    negative_flag <= 0;
                end
                // 初始向量設定為 (1/K, 0)
                x_reg      <= SCALE_FACTOR;
                y_reg      <= 0;
                iter_count <= 0;
                running    <= 1;
                output_valid <= 0;
            end else if (running) begin
                if (iter_count < TOTAL_ITER) begin
                    // 進行一次迭代更新
                    x_reg      <= x_next;
                    y_reg      <= y_next;
                    z_reg      <= z_next;
                    iter_count <= iter_count + 1;
                end else begin
                    // 完成迭代後組合結果
                    exp_x <= (tmp_result + (1 << 22)) >>> 23;  // Q8.54 -> Q0.31（進行四捨五入）
                    output_valid <= 1;
                    running <= 0;
                end
            end else begin
                output_valid <= 0;
            end
        end
    end 

    //-------------------------------------------------------------------------
    // 在模擬時期印出迭代的內部暫存器值（僅用於模擬，合成時會忽略）
    // 這裡使用 initial block 加上 $monitor 或者在 always block 裡面用 $display
    // 下面在 always block 的 posedge clk 時，若 running 為真則印出數值。
    // always @(posedge clk) begin
    //     if (running) begin
    //         $display("Time=%0t: iter=%0d, shift=%0d, x_reg=%h, y_reg=%h, z_reg=%h", 
    //                   $time, iter_count, shift_value, x_reg, y_reg, z_reg);
    //     end
    // end



endmodule
