// `timescale 1ns / 1ps
// `include "params.vh"

// module ADD_tb;

//     // 假設 params.vh 中定義：
//     // `define INT8_SIZE 8
//     // `define INT32_SIZE 32
//     localparam INT8_SIZE      = 8;
//     localparam INT32_SIZE     = 32;
//     localparam MAX_VECTOR_SIZE = 8;
    
//     // 時脈與重置
//     reg clk;
//     reg rst;
//     reg valid_in;
    
//     // 輸入向量 (一次 8 筆 8-bit 資料)
//     reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input1;
//     reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input2;
    
//     // 量化參數 (期間鎖存)
//     reg signed [INT32_SIZE-1:0] input1_offset;
//     reg signed [INT32_SIZE-1:0] input2_offset;
//     reg [INT32_SIZE-1:0] left_shift; 
//     reg signed [INT32_SIZE-1:0] input1_multiplier;
//     reg signed [INT32_SIZE-1:0] input2_multiplier;
//     reg signed [INT32_SIZE-1:0] input1_shift;
//     reg signed [INT32_SIZE-1:0] input2_shift;
//     reg signed [INT32_SIZE-1:0] output_multiplier;
//     reg signed [INT32_SIZE-1:0] output_shift;
//     reg signed [INT32_SIZE-1:0] output_offset;
//     reg signed [31:0] quantized_activation_min;
//     reg signed [31:0] quantized_activation_max;
    
//     // DUT 輸出
//     wire [INT8_SIZE*MAX_VECTOR_SIZE-1:0] data_o;
//     wire valid_o;
    
//     // 實例化 ADD 模組
//     ADD #(.MAX_VECTOR_SIZE(MAX_VECTOR_SIZE)) dut (
//         .clk(clk),
//         .rst(rst),
//         .valid_in(valid_in),
//         .input1(input1),
//         .input2(input2),
//         .input1_offset(input1_offset),
//         .input2_offset(input2_offset),
//         .left_shift(left_shift),
//         .input1_multiplier(input1_multiplier),
//         .input2_multiplier(input2_multiplier),
//         .input1_shift(input1_shift),
//         .input2_shift(input2_shift),
//         .output_multiplier(output_multiplier),
//         .output_shift(output_shift),
//         .output_offset(output_offset),
//         .quantized_activation_min(quantized_activation_min),
//         .quantized_activation_max(quantized_activation_max),
//         .data_o(data_o),
//         .valid_o(valid_o)
//     );
    
//     // 時脈產生 (週期 10 ns)
//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk;
//     end

//     // FSDB dump (可選)
//     initial begin
//         $fsdbDumpfile("verdi.fsdb");
//         $fsdbDumpvars(0, ADD_tb, "+all");
//     end
    
//     // 用來存放 5 筆測試結果與預期結果 (每組 8 筆資料)
//     reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_results [0:4];
//     reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] expected_results [0:4];
    
//     // task 捕捉一次測試結果
//     task capture_result(input integer index);
//         begin
//             // 等待 valid_o 變高（管線完成）
//             @(posedge valid_o);
//             #1; // 確保資料穩定
//             test_results[index] = data_o;
//             $display("Test case %0d result: %h", index, data_o);
//         end
//     endtask
    
//     // 測試激勵與參數設定
//     initial begin
//         valid_in = 0;
//         // 固定參數設定 (皆與給定數值一致)
//         input1_offset      = 32'sd105;
//         input2_offset      = 32'sd100;
//         left_shift         = 32'd20;
        
//         input1_multiplier  = 32'sd2090768454;
//         input2_multiplier  = 32'sd1073741824;
//         input1_shift       = -32'sd1;
//         input2_shift       = 32'sd0;
        
//         output_multiplier  = 32'sd1073741824;
//         output_shift       = -32'sd18;
//         output_offset      = -32'sd100;
        
//         quantized_activation_min = -32'sd128;
//         quantized_activation_max = 32'sd127;
        
//         // 初始 rst 低 20 ns，再拉高
//         rst = 0;
//         #20; rst = 1;
//         #50; // 讓管線清空
        
//         // -------------------------------
//         // Test Case 0  
//         // 依照元素順序 (index0 ~ index7)：
//         // input1: -111, -101, -110, -108, -104, -110, -101, -105  
//         // input2: -100, -101, -102, -98, -101, -99, -99, -100  
//         // expected: -106, -97, -107, -101, -100, -104, -95, -100  
//         // 組合時需由 element7 到 element0：
//         input1 = { -8'sd105, -8'sd101, -8'sd110, -8'sd104, -8'sd108, -8'sd110, -8'sd101, -8'sd111 };
//         input2 = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
//         @(negedge clk); 
//         valid_in = 1;
//         // @(negedge clk);
//         @(negedge clk);
//         valid_in = 0;
        
//         #10;
//         capture_result(0);
//         #20;
        
//         // -------------------------------
//         // Test Case 1  
//         // input1: -105, -97, -106, -104, -108, -97, -108, -104  
//         // input2: -99,  -100, -101, -99,  -98,  -99,  -99,  -100  
//         // expected: -99, -92, -102, -98, -101, -91, -102, -99  
//         // input1 = { -8'sd(-104) /*這裡先放個placeholder，接下來用正確排列*/, 
//         //             -8'sd108, -8'sd97, -8'sd106, -8'sd104, -8'sd97, -8'sd105, -8'sd105 };
//         // 注意：上面 placeholder 部分請改為正確的排列；以下給出正確排列範例：
//         input1 = { -8'sd104, -8'sd108, -8'sd97, -8'sd108, -8'sd104, -8'sd106, -8'sd97, -8'sd105 };
//         input2 = { -8'sd100, -8'sd99, -8'sd99, -8'sd98, -8'sd99, -8'sd101, -8'sd100, -8'sd99 };
//         @(negedge clk); 
//         valid_in = 1;
//         @(negedge clk);
//         valid_in = 0;
//         #10;
//         capture_result(1);
//         #20;
        
//         // -------------------------------
//         // Test Case 2  
//         // input1: -113, -103, -106, -110, -107, -112, -104, -99  
//         // input2: -100, -101, -102, -98,  -101, -99,  -99,  -100  
//         // expected: -108, -99, -103, -103, -103, -106, -98, -94  
//         input1 = { -8'sd99, -8'sd104, -8'sd112, -8'sd107, -8'sd110, -8'sd106, -8'sd103, -8'sd113 };
//         input2 = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
//         @(negedge clk); 
//         valid_in = 1;
//         @(negedge clk);
//         valid_in = 0;
//         #10;
//         capture_result(2);
//         #20;
        
//         // -------------------------------
//         // Test Case 3  
//         // input1: -103, -96, -108, -102, -110, -97, -109, -109  
//         // input2: -99,  -100, -101, -100, -98,  -99,  -99,  -100  
//         // expected: -97, -91, -104, -97, -103, -91, -103, -104  
//         input1 = { -8'sd109, -8'sd109, -8'sd97, -8'sd110, -8'sd102, -8'sd108, -8'sd96, -8'sd103 };
//         input2 = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd98,  -8'sd100, -8'sd101, -8'sd100, -8'sd99 };
//         @(negedge clk); 
//         valid_in = 1;
//         @(negedge clk);
//         valid_in = 0;
//         #10;
//         capture_result(3);
//         #20;
        
//         // -------------------------------
//         // Test Case 4  
//         // input1: -113, -103, -106, -110, -107, -112, -104, -99  
//         // input2: -100, -101, -102, -98,  -101, -99,  -99,  -100  
//         // expected: -108, -99, -103, -103, -103, -106, -98, -94  
//         input1 = { -8'sd99, -8'sd104, -8'sd112, -8'sd107, -8'sd110, -8'sd106, -8'sd103, -8'sd113 };
//         input2 = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
//         @(negedge clk); 
//         valid_in = 1;
//         @(negedge clk);
//         valid_in = 0;
//         #10;
//         capture_result(4);
//         #20;
        
//         // 設定 expected_results (組合順序同上)
//         expected_results[0] = { -8'sd100, -8'sd95, -8'sd104, -8'sd100, -8'sd101, -8'sd107, -8'sd97, -8'sd106 };
//         // expected: -99, -92, -102, -98, -101, -91, -102, -99  
//         expected_results[1] = { -8'sd99, -8'sd102, -8'sd91, -8'sd101, -8'sd98, -8'sd102, -8'sd92, -8'sd99 };
//         expected_results[2] = { -8'sd94, -8'sd98, -8'sd106, -8'sd103, -8'sd103, -8'sd103, -8'sd99, -8'sd108 };
//         expected_results[3] = { -8'sd104, -8'sd103, -8'sd91, -8'sd103, -8'sd97, -8'sd104, -8'sd91, -8'sd97 };
//         expected_results[4] = { -8'sd94, -8'sd98, -8'sd106, -8'sd103, -8'sd103, -8'sd103, -8'sd99, -8'sd108 };
        
//         check_results();
//         $finish;
//     end
    
//     // 比對 DUT 輸出與預期
//     task check_results;
//         integer i, j;
//         reg correct;
//         reg signed [INT8_SIZE-1:0] out_val, exp_val;
//         begin
//             correct = 1;
//             for(i = 0; i < 5; i = i + 1) begin
//                 for(j = 0; j < MAX_VECTOR_SIZE; j = j + 1) begin
//                     out_val = test_results[i][(j+1)*INT8_SIZE-1 -: INT8_SIZE];
//                     exp_val = expected_results[i][(j+1)*INT8_SIZE-1 -: INT8_SIZE];
//                     if (out_val !== exp_val) begin
//                         $display("Mismatch in Test Case %0d, Element %0d: expected %d, got %d", 
//                                  i, j, exp_val, out_val);
//                         correct = 0;
//                     end else begin
//                         $display("Match in Test Case %0d, Element %0d: got %d", i, j, out_val);
//                     end
//                 end
//             end
//             if (correct)
//                 $display("All test cases passed!");
//             else
//                 $display("Some test cases FAILED.");
//         end
//     endtask

// endmodule


`timescale 1ns / 1ps
`include "params.vh"

module ADD_tb;

    // 假設 params.vh 中定義：
    // `define INT8_SIZE 8
    // `define INT32_SIZE 32
    localparam INT8_SIZE      = 8;
    localparam INT32_SIZE     = 32;
    localparam MAX_VECTOR_SIZE = 8;
    localparam NUM_TESTS = 5;
    
    // 時脈與重置
    reg clk;
    reg rst;
    reg valid_in;
    
    // 輸入向量 (一次 8 筆 8-bit 資料)
    reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input1;
    reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input2;
    
    // 量化參數 (期間鎖存)
    reg signed [INT32_SIZE-1:0] input1_offset;
    reg signed [INT32_SIZE-1:0] input2_offset;
    reg [INT32_SIZE-1:0] left_shift; 
    reg signed [INT32_SIZE-1:0] input1_multiplier;
    reg signed [INT32_SIZE-1:0] input2_multiplier;
    reg signed [INT32_SIZE-1:0] input1_shift;
    reg signed [INT32_SIZE-1:0] input2_shift;
    reg signed [INT32_SIZE-1:0] output_multiplier;
    reg signed [INT32_SIZE-1:0] output_shift;
    reg signed [INT32_SIZE-1:0] output_offset;
    reg signed [31:0] quantized_activation_min;
    reg signed [31:0] quantized_activation_max;
    
    // DUT 輸出
    wire [INT8_SIZE*MAX_VECTOR_SIZE-1:0] data_o;
    wire valid_o;
    
    // 實例化 ADD 模組
    ADD #(.MAX_VECTOR_SIZE(MAX_VECTOR_SIZE)) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .input1(input1),
        .input2(input2),
        .input1_offset(input1_offset),
        .input2_offset(input2_offset),
        .left_shift(left_shift),
        .input1_multiplier(input1_multiplier),
        .input2_multiplier(input2_multiplier),
        .input1_shift(input1_shift),
        .input2_shift(input2_shift),
        .output_multiplier(output_multiplier),
        .output_shift(output_shift),
        .output_offset(output_offset),
        .quantized_activation_min(quantized_activation_min),
        .quantized_activation_max(quantized_activation_max),
        .data_o(data_o),
        .valid_o(valid_o)
    );
    
    // 時脈產生 (週期 10 ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // FSDB dump (可選)
    initial begin
        $fsdbDumpfile("verdi.fsdb");
        $fsdbDumpvars(0, ADD_tb, "+all");
    end
    
    // 用來存放測試結果與預期結果 (每組 8 筆資料)
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_results [0:NUM_TESTS-1];
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] expected_results [0:NUM_TESTS-1];

    // 定義測試資料 (順序從 element7 到 element0)
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_input1 [0:NUM_TESTS-1];
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_input2 [0:NUM_TESTS-1];

    initial begin
        // Test Case 0
        test_input1[0] = { -8'sd105, -8'sd101, -8'sd110, -8'sd104, -8'sd108, -8'sd110, -8'sd101, -8'sd111 };
        test_input2[0] = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
        // Test Case 1
        test_input1[1] = { -8'sd104, -8'sd108, -8'sd97, -8'sd108, -8'sd104, -8'sd106, -8'sd97, -8'sd105 };
        test_input2[1] = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd98,  -8'sd99,  -8'sd101, -8'sd100, -8'sd99 };
        // Test Case 2
        test_input1[2] = { -8'sd99, -8'sd104, -8'sd112, -8'sd107, -8'sd110, -8'sd106, -8'sd103, -8'sd113 };
        test_input2[2] = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
        // Test Case 3
        test_input1[3] = { -8'sd109, -8'sd109, -8'sd97, -8'sd110, -8'sd102, -8'sd108, -8'sd96, -8'sd103 };
        test_input2[3] = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd98,  -8'sd100, -8'sd101, -8'sd100, -8'sd99 };
        // Test Case 4
        test_input1[4] = { -8'sd99, -8'sd104, -8'sd112, -8'sd107, -8'sd110, -8'sd106, -8'sd103, -8'sd113 };
        test_input2[4] = { -8'sd100, -8'sd99,  -8'sd99,  -8'sd101, -8'sd98,  -8'sd102, -8'sd101, -8'sd100 };
    end

    // 定義預期結果 (每個元素依序從 element7 到 element0)
    initial begin
        expected_results[0] = { -8'sd100, -8'sd95, -8'sd104, -8'sd100, -8'sd101, -8'sd107, -8'sd97, -8'sd106 };
        expected_results[1] = { -8'sd99,  -8'sd102, -8'sd91, -8'sd101, -8'sd98, -8'sd102, -8'sd92, -8'sd99 };
        expected_results[2] = { -8'sd94, -8'sd98, -8'sd106, -8'sd103, -8'sd103, -8'sd103, -8'sd99, -8'sd108 };
        expected_results[3] = { -8'sd104, -8'sd103, -8'sd91,  -8'sd103, -8'sd97, -8'sd104, -8'sd91, -8'sd97 };
        expected_results[4] = { -8'sd94, -8'sd98, -8'sd106, -8'sd103, -8'sd103, -8'sd103, -8'sd99, -8'sd108 };
    end
    // 使用獨立的 index 控制送入與捕捉
    integer feed_index;
    integer capture_index = 0;
    integer error_count = 0;

    // 連續送入所有測試案例
    initial begin
        valid_in = 0;
        // 固定參數設定
        input1_offset      = 32'sd105;
        input2_offset      = 32'sd100;
        left_shift         = 32'd20;
        input1_multiplier  = 32'sd2090768454;
        input2_multiplier  = 32'sd1073741824;
        input1_shift       = -32'sd1;
        input2_shift       = 32'sd0;
        output_multiplier  = 32'sd1073741824;
        output_shift       = -32'sd18;
        output_offset      = -32'sd100;
        quantized_activation_min = -32'sd128;
        quantized_activation_max = 32'sd127;
        
        rst = 0;
        #20; rst = 1;
        #50; // 讓管線清空

        for (feed_index = 0; feed_index < NUM_TESTS; feed_index = feed_index + 1) begin
            @(negedge clk);
            input1 = test_input1[feed_index];
            input2 = test_input2[feed_index];
            valid_in = 1;
            @(negedge clk);
            valid_in = 0;
        end
    end

    // 使用 always block 捕捉 valid_o 上升時的結果並立即比對預期值
    always @(posedge clk) begin
        if (valid_o) begin
            reg signed [INT8_SIZE-1:0] dut_result;
            reg signed [INT8_SIZE-1:0] exp_result;
            integer j;
            $display("Captured Test case %0d result: %h", capture_index, data_o);
            for (j = 0; j < MAX_VECTOR_SIZE; j = j + 1) begin
                dut_result = data_o[(j+1)*INT8_SIZE-1 -: INT8_SIZE];
                exp_result = expected_results[capture_index][(j+1)*INT8_SIZE-1 -: INT8_SIZE];
                if (dut_result !== exp_result) begin
                    $display("Mismatch in Test Case %0d, Element %0d: expected %d, got %d", capture_index, j, exp_result, dut_result);
                    error_count = error_count + 1;
                end else begin
                    $display("Match in Test Case %0d, Element %0d: got %d", capture_index, j, dut_result);
                end
            end
            capture_index = capture_index + 1;
            // 如果已捕捉所有案例，則檢查結果並結束模擬
            if (capture_index == NUM_TESTS) begin
                if (error_count == 0)
                    $display("TEST PASSED: All test cases passed!");
                else
                    $display("TEST FAILED: %0d errors detected.", error_count);
                $finish;
            end
        end
    end

endmodule
