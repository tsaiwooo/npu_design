`timescale 1ns / 1ps
`include "params.vh"

module MUL_tb;

    // Assume params.vh defines:
    // `define INT8_SIZE 8
    // `define INT32_SIZE 32
    localparam INT8_SIZE      = 8;
    localparam INT32_SIZE     = 32;
    localparam MAX_VECTOR_SIZE = 8;
    localparam NUM_TESTS = 5;
    
    // Clock and reset
    reg clk;
    reg rst;
    reg valid_in;
    
    // Input vectors (8 pieces of 8-bit data at a time)
    reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input1;
    reg [INT8_SIZE*MAX_VECTOR_SIZE-1:0] input2;
    
    // Quantization parameters
    reg signed [INT32_SIZE-1:0] input1_offset;
    reg signed [INT32_SIZE-1:0] input2_offset;
    reg signed [INT32_SIZE-1:0] output_multiplier;
    reg signed [INT32_SIZE-1:0] output_shift;
    reg signed [INT32_SIZE-1:0] output_offset;
    reg signed [31:0] quantized_activation_min;
    reg signed [31:0] quantized_activation_max;
    
    // DUT outputs
    wire [INT8_SIZE*MAX_VECTOR_SIZE-1:0] data_o;
    wire valid_o;
    
    // Instantiate the MUL module
    MUL #(.MAX_VECTOR_SIZE(MAX_VECTOR_SIZE)) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .input1(input1),
        .input2(input2),
        .input1_offset(input1_offset),
        .input2_offset(input2_offset),
        .output_multiplier(output_multiplier),
        .output_shift(output_shift),
        .output_offset(output_offset),
        .quantized_activation_min(quantized_activation_min),
        .quantized_activation_max(quantized_activation_max),
        .data_o(data_o),
        .valid_o(valid_o)
    );
    
    // Clock generation (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // FSDB dump (optional)
    initial begin
        $fsdbDumpfile("verdi.fsdb");
        $fsdbDumpvars(0, MUL_tb, "+all");
    end

    // Used to store test results and expected results (8 data items per group)
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_results [0:NUM_TESTS-1];
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] expected_results [0:NUM_TESTS-1];
    // Declare test data array (from element 7 to element 0)
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_input1 [0:NUM_TESTS-1];
    reg signed [INT8_SIZE*MAX_VECTOR_SIZE-1:0] test_input2 [0:NUM_TESTS-1];

    // Test Case 0
initial begin
    test_input1[0] = { -8'sd5, -8'sd4, -8'sd5, 8'd1, -8'sd7, -8'sd8, -8'sd10, -8'sd6 };
    test_input2[0] = { 8'd0, 8'd1, 8'd0, 8'd4, -8'sd1, -8'sd2, -8'sd3, -8'sd1 };
    expected_results[0] = { -8'sd71, -8'sd70, -8'sd71, -8'sd65, -8'sd73, -8'sd74, -8'sd76, -8'sd72 };
end

// Test Case 1
initial begin
    test_input1[1] = { -8'sd11, -8'sd4, -8'sd9, 8'sd0, -8'sd2, -8'sd7, -8'sd8, -8'sd6 };
    test_input2[1] = { -8'sd4, 8'd1, -8'sd2, 8'd3, 8'd2, -8'sd1, -8'sd2, -8'sd1 };
    expected_results[1] = { -8'sd77, -8'sd70, -8'sd75, -8'sd66, -8'sd68, -8'sd73, -8'sd74, -8'sd72 };
end

// Test Case 2
initial begin
    test_input1[2] = { -8'sd5, -8'sd5, -8'sd2, -8'sd10, -8'sd4, -8'sd3, 8'sd1, -8'sd7 };
    test_input2[2] = { 8'd0, 8'd0, 8'd2, -8'sd3, 8'd1, 8'd1, 8'd4, -8'sd1 };
    expected_results[2] = { -8'sd71, -8'sd71, -8'sd68, -8'sd76, -8'sd70, -8'sd69, -8'sd65, -8'sd73 };
end

// Test Case 3
initial begin
    test_input1[3] = { -8'sd6, -8'sd9, -8'sd8, -8'sd4, -8'sd2, -8'sd5, -8'sd7, -8'sd3 };
    test_input2[3] = { -8'sd1, -8'sd2, -8'sd2, 8'd1, 8'd2, 8'd1, -8'sd1, 8'd1 };
    expected_results[3] = { -8'sd72, -8'sd75, -8'sd74, -8'sd70, -8'sd68, -8'sd71, -8'sd73, -8'sd69 };
end

// Test Case 4
initial begin
    test_input1[4] = { -8'sd6, -8'sd5, -8'sd2, -8'sd6, -8'sd10, -8'sd5, 8'd6, -8'sd8 };
    test_input2[4] = { -8'sd1, 8'd0, 8'd2, -8'sd1, -8'sd3, 8'd0, 8'd7, -8'sd2 };
    expected_results[4] = { -8'sd72, -8'sd71, -8'sd68, -8'sd72, -8'sd76, -8'sd71, -8'sd60, -8'sd74 };
end

// Test Case 5
initial begin
    test_input1[5] = { -8'sd4, 8'd1, -8'sd13, -8'sd5, -8'sd4, 8'd2, -8'sd15, -8'sd2 };
    test_input2[5] = { 8'd1, 8'd4, -8'sd5, 8'd0, 8'd1, 8'd4, -8'sd6, 8'd2 };
    expected_results[5] = { -8'sd70, -8'sd65, -8'sd78, -8'sd71, -8'sd70, -8'sd64, -8'sd80, -8'sd68 };
end




    // Use independent index to control feeding and capturing
    integer feed_index;
    integer capture_index = 0;
    integer error_count = 0;

    // Feed all test cases sequentially
    initial begin
        valid_in = 0;
        // Set fixed parameters
        input1_offset      = 32'sd5;
        input2_offset      = 32'sd128;
        output_multiplier  = 32'sd2071220384;
        output_shift       = -32'sd7;
        output_offset      = -32'sd71;
        quantized_activation_min = -32'sd128;
        quantized_activation_max = 32'sd127;
        
        rst = 0;
        #20; rst = 1;
        #50; // Let the pipeline clear

        for (feed_index = 0; feed_index < NUM_TESTS; feed_index = feed_index + 1) begin
            @(negedge clk);
            input1 = test_input1[feed_index];
            input2 = test_input2[feed_index];
            valid_in = 1;
            @(negedge clk);
            valid_in = 0;
        end
    end

    // Use always block to capture results when valid_o rises and compare with expected values
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
