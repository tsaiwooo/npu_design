`timescale 1ns / 1ps

module RoundingDivideByPOT_tb;

    // Inputs
    reg signed [31:0] x;
    reg [4:0] exponent;  // 5 bits for exponent (0-31)

    // Output
    wire signed [31:0] result;

    // Instantiate the Unit Under Test (UUT)
    RoundingDivideByPOT uut (
        .x(x),
        .exponent(exponent),
        .result(result)
    );

    // Counters for pass/fail
    integer pass_count = 0;
    integer fail_count = 0;

    // Function to calculate the expected result (golden model)
    function signed [31:0] golden_rounding_divide_by_pot;
        input signed [31:0] x;
        input [4:0] exponent;

        reg signed [31:0] mask;
        reg signed [31:0] remainder;
        reg signed [31:0] threshold;
        reg signed [31:0] shifted_x;
        begin
            mask = (1 << exponent) - 1;
            remainder = x & mask;
            threshold = (mask >> 1) + (x < 0 ? 1 : 0);
            shifted_x = x >>> exponent;
            golden_rounding_divide_by_pot = shifted_x + ((remainder > threshold) || (remainder == threshold && (shifted_x & 1)));
        end
    endfunction

    // Task to check result and display comparison
    task check_result;
        input integer test_case_num;
        input signed [31:0] x;
        input [4:0] exponent;
        reg signed [31:0] expected;
        begin
            expected = golden_rounding_divide_by_pot(x, exponent);
            $display("Test Case %0d: x = %0d, exponent = %0d", test_case_num, x, exponent);
            $display("Result: %0d, Expected: %0d", result, expected);

            if (result === expected) begin
                $display("Test Case %0d PASSED", test_case_num);
                pass_count = pass_count + 1;
            end else begin
                $display("Test Case %0d FAILED", test_case_num);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Initialize and apply test cases
    initial begin
        $display("Starting Testbench...");

        // Test Case 1
        #10;
        x = 1000;
        exponent = 2;
        #10;
        check_result(1, x, exponent);

        // Test Case 2
        #10;
        x = -1000;
        exponent = 2;
        #10;
        check_result(2, x, exponent);

        // Test Case 3
        #10;
        x = 12345;
        exponent = 5;
        #10;
        check_result(3, x, exponent);

        // Test Case 4
        #10;
        x = -12345;
        exponent = 5;
        #10;
        check_result(4, x, exponent);

        // Test Case 5
        #10;
        x = 32'h7FFFFFFF;
        exponent = 1;
        #10;
        check_result(5, x, exponent);

        // Test Case 6
        #10;
        x = 32'h80000000;
        exponent = 1;
        #10;
        check_result(6, x, exponent);

        // Test Case 7
        #10;
        x = 0;
        exponent = 15;
        #10;
        check_result(7, x, exponent);

        // Test Case 8
        #10;
        x = 100;
        exponent = 0;
        #10;
        check_result(8, x, exponent);

        // Test Case 9
        #10;
        x = -2000;
        exponent = 3;
        #10;
        check_result(9, x, exponent);

        // Test Case 10
        #10;
        x = 32768;
        exponent = 4;
        #10;
        check_result(10, x, exponent);

        // Display final results
        $display("------------------------------------------------");
        $display("Total PASS Count: %0d", pass_count);
        $display("Total FAIL Count: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("************************************************");
            $display("*       ALL TESTS PASSED! Congratulations!     *");
            $display("************************************************");
        end else begin
            $display("Some tests failed. Please review the errors.");
        end

        $finish;
    end

endmodule
