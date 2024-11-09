`timescale 1ns / 1ps

module MultiplyByQuantizedMultiplier_tb;

    // Inputs
    reg clk;
    reg rst;
    reg input_valid;
    reg [31:0] x;
    reg [31:0] quantized_multiplier;
    reg signed [31:0] shift;

    // Outputs
    wire output_valid;
    wire signed [31:0] x_mul_by_quantized_multiplier;

    // Pass/Fail Counters
    integer pass_count = 0;
    integer fail_count = 0;
    integer total_tests = 6;  // Total number of tests in this testbench

    // Instantiate the Unit Under Test (UUT)
    MultiplyByQuantizedMultiplier uut (
        .clk(clk),
        .rst(rst),
        .x(x),
        .quantized_multiplier(quantized_multiplier),
        .shift(shift),
        .input_valid(input_valid),
        .output_valid(output_valid),
        .x_mul_by_quantized_multiplier(x_mul_by_quantized_multiplier)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Golden Model for reference calculation
    function signed [31:0] golden_multiply_by_quantized_multiplier(
        input [31:0] x,
        input [31:0] quantized_multiplier,
        input signed [31:0] shift
    );
        reg signed [63:0] ab_64;
        reg [31:0] remainder, threshold;
        reg [31:0] left_shift, right_shift;
        reg signed [31:0] ab_x2_high32;
        reg signed [31:0] nudge;
        reg [31:0] mask;
        reg overflow;
        
        begin
            // Calculate left_shift and right_shift based on shift value
            left_shift = (shift > 0) ? shift : 0;
            right_shift = (shift > 0) ? 0 : -shift;

            // Step 1: x * (1 << left_shift)
            ab_64 = x * (1 << left_shift);

            // Step 2: Multiply with quantized_multiplier and handle overflow
            ab_64 = ab_64 * quantized_multiplier;
            // if (ab_64 == 64'h8000000000000000)
            //     ab_64 = 32'h7FFFFFFF;  // Handle overflow case
            overflow = (x == quantized_multiplier && x == 32'h80000000);
            // Step 3: Add nudge for rounding
            nudge = (ab_64 >= 0) ? (1 << 30) : (1 - (1 << 30));
            ab_x2_high32 = overflow? 32'h7fffffff : (ab_64 + nudge) >> 31;
            mask = (1 << right_shift) - 1;
            // Step 4: Calculate remainder and threshold for rounding
            remainder = ab_x2_high32 & mask;
            threshold = mask >> 1;
            if (ab_x2_high32 < 0)
                threshold = threshold + 1;

            // Step 5: Rounding and shift right by right_shift
            golden_multiply_by_quantized_multiplier = ab_x2_high32 >> right_shift;
            if (remainder > threshold || 
               (remainder == threshold && (ab_x2_high32 & 1) && ab_x2_high32 != 32'h7fffffff))
                golden_multiply_by_quantized_multiplier = golden_multiply_by_quantized_multiplier + 1;
        end
    endfunction

    // Initialize and apply test cases
    initial begin
        // Initialize inputs
        clk = 0;
        rst = 1;
        input_valid = 0;
        x = 0;
        quantized_multiplier = 0;
        shift = 0;

        // Apply reset
        #10;
        rst = 0;
        #10;
        rst = 1;

        // Test case 1: Basic multiplication with positive values
        #10;
        x = 32'd1000;
        quantized_multiplier = 32'd2000;
        shift = 2;
        input_valid = 1;
        #10;
        input_valid = 0;

        // Wait for output_valid to go high and compare with Golden Model
        wait (output_valid == 1);
        #10;
        check_result(1, x, quantized_multiplier, shift);

        // Test case 2: Overflow scenario
        #10;
        x = 32'h80000000;  // minimum 32-bit integer
        quantized_multiplier = 32'h80000000;
        shift = 1;
        input_valid = 1;
        #10;
        input_valid = 0;

        wait (output_valid == 1);
        #10;
        check_result(2, x, quantized_multiplier, shift);

        // Test case 3: Negative multiplication with rounding
        #10;
        x = -32'd1500;
        quantized_multiplier = 32'd1000;
        shift = -3;
        input_valid = 1;
        #10;
        input_valid = 0;

        wait (output_valid == 1);
        #10;
        check_result(3, x, quantized_multiplier, shift);

        // Test case 4: Large positive shift with small multiplier
        #10;
        x = 32'd500;
        quantized_multiplier = 32'd10;
        shift = 10;
        input_valid = 1;
        #10;
        input_valid = 0;

        wait (output_valid == 1);
        #10;
        check_result(4, x, quantized_multiplier, shift);

        // Test case 5: Small values and large negative shift
        #10;
        x = 32'd1;
        quantized_multiplier = 32'd3;
        shift = -10;
        input_valid = 1;
        #10;
        input_valid = 0;

        wait (output_valid == 1);
        #10;
        check_result(5, x, quantized_multiplier, shift);

        // Test case 6: Edge case with shift = 0
        #10;
        x = 32'd1024;
        quantized_multiplier = 32'd2048;
        shift = 0;
        input_valid = 1;
        #10;
        input_valid = 0;

        wait (output_valid == 1);
        #10;
        check_result(6, x, quantized_multiplier, shift);

        // Test case 7: Basic multiplication with right shift
        #10;
        x = 32'd1234;
        quantized_multiplier = 32'd5678;
        shift = -1;
        input_valid = 1;
        #10;
        input_valid = 0;
        wait (output_valid == 1);
        #10;
        check_result(1, x, quantized_multiplier, shift);

        // Test case 8: Zero multiplication
        #10;
        x = 32'd0;
        quantized_multiplier = 32'd2000;
        shift = 3;
        input_valid = 1;
        #10;
        input_valid = 0;
        wait (output_valid == 1);
        #10;
        check_result(2, x, quantized_multiplier, shift);

        // Display final results
        #10;
        $display("------------------------------------------------");
        $display("Total PASS Count: %0d", pass_count);
        $display("Total FAIL Count: %0d", fail_count);
        
        // If all tests passed, print success message
        if (fail_count == 0) begin
            $display("%s", "                                                                      :+**************-.            ");
            $display("%s", "                                                                     :+****************.            ");
            $display("%s", "                                                                     :+*****++++*******.            ");
            $display("%s", "                                                                     :+*****:.-..=*****.            ");
            $display("%s", "                                                                     :+*****:.-:.=*****.            ");
            $display("%s", "                                                                     :+*****::++*******.            ");
            $display("%s", "                                                                     :+*****--*********.            ");
            $display("%s", "                                     ..                   .=*+.      :+****************.            ");
            $display("%s", "                         .:--.     :*##*:                .*###++=.   :+****************.            ");
            $display("%s", "          .+##*-.       .+####+.  :#####-     .=###-. :*#########+.  :+***+=-::::-++***.            ");
            $display("%s", "         .*#####:        +#####+..*#####-     .=####=.*#########++*###*+:.                          ");
            $display("%s", "         .######:        :######:.*####*:     .:####+..::-###############*.                         ");
            $display("%s", "         .+#####-        .+#####-.=####*:      .+###*.  .-#####*+-:::=####+.                        ");
            $display("%s", "          -#####+.       .+#####: :#####-       =###*...+#####-      .=###*.                        ");
            $display("%s", "          .*#####:        :*##+:. .+#####-.     .+*=..:*######-  ... .+###+.                        ");
            $display("%s", "           :######:.       ...     .*#####+.          -#######::*########*:.                        ");
            $display("%s", "           .:######+.               .*#####-          ...-###*:###*-####*.                          ");
            $display("%s", "            .-######*.               .:*#*=.            .-###+.:*#########:.                        ");
            $display("%s", "              :*####*.                   .......         .++-.  .... .=###=.                        ");
            $display("%s", "               .:==-..              .:+#%#***##%#=.                  ..:..                         ");
            $display("%s", "                                .-*#+-............:+#*-.               ..:..                        ");
            $display("%s", "           .....    ..-*##*=..:#%=....................-%#::*%%%*.. ...:..                          ");
            $display("%s", "            ..::.   =#-....:#%=.........................:##.....:**.....                            ");
            $display("%s", "               .:. :#.....:%+.....................................#- ....:..                        ");
            $display("%s", "           ......  =*.............................................*= .......                        ");
            $display("%s", "           ....:.. .#=...........................................-#:                                ");
            $display("%s", "                    .*%=#-....................................:%@*.  .:....                         ");
            $display("%s", "                 ..   :#-.........................--............*=    ...::.                        ");
            $display("%s", "            ...::... :%-........-%@%:...-+***+-..-%@%:..........-#:                                 ");
            $display("%s", "            ....    .#+..........:...=%#::=+-.-#%:...............**.                                ");
            $display("%s", "                    -#.............=%=.-%@@%=....*+..............:%##:                             ");
            $display("%s", "              .=%##:*=...........-%+.....=#.....-=*#.............=#:.++                             ");
            $display("%s", "              =*..=@#:..........-%:=@#=::-#::=*%%@*=#............=#:.#%%+.                         ");
            $display("%s", "             .*+..=@*...........*=:%%+---==---=##-..**............%-#+...*+.                        ");
            $display("%s", "           .+%#@#*-%*...........#=....-*#%%%#++:.....-@:..........:%:-%-..*+.                        ");
            $display("%s", "           -%:...-#:#-..........*+......==-:-*#.....+#...........:%:.##..++.                        ");
            $display("%s", "           -%:...=%:++..........:#*:.....:-=:.....:*#.............#=.+#+=*+.                        ");
            $display("%s", "           .#=...:#-++............:=#%@@%%%%%#%*=...............#=.=+*%=.                         ");
            $display("%s", "            .**=+#+.*%-.........................................=%-.#+..                            ");
            $display("%s", "              ...#=...+%#+=..................................-%#-.-#-                               ");
            $display("%s", "                 .=%+............................................**.                                ");
            $display("%s", "                    .=*#*.....................................:#*:                                  ");
            $display("%s", "                      .=%.....................................:%:                                   ");
            $display("%s", "                      .:-......................................-.                                   ");
        end else begin
            $display("Some tests failed. Please review the errors.");
        end

        // Finish simulation
        $finish;
    end

    // Task to check results and print if they match the Golden Model
    task check_result;
        input integer test_case_num;
        input [31:0] x;
        input [31:0] quantized_multiplier;
        input signed [31:0] shift;

        reg [31:0] expected;
        begin
            expected = golden_multiply_by_quantized_multiplier(x, quantized_multiplier, shift);
            $display("Test Case %0d: x = %d, quantized_multiplier = %d, shift = %d", test_case_num, x, quantized_multiplier, shift);
            $display("Hardware Result: %d", x_mul_by_quantized_multiplier);
            $display("Golden Model Result: %d", expected);

            if (x_mul_by_quantized_multiplier == expected) begin
                $display("Test Case %0d PASSED", test_case_num);
                pass_count = pass_count + 1;
            end else begin
                $display("Test Case %0d FAILED", test_case_num);
                fail_count = fail_count + 1;
            end
        end
    endtask

endmodule
