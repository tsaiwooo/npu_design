`timescale 1ns / 1ps

module reciprocal_over_1_tb;

    // Clock and reset signals
    reg clk;
    reg rst;

    // Interface signals to the device under test (DUT)
    reg [31:0] x;
    reg [3:0] x_integer_bits;
    reg input_valid;
    wire [31:0] reciprocal;
    wire output_valid;

    // Instantiate the device under test
    reciprocal_over_1 uut (
        .clk(clk),
        .rst(rst),
        .x(x),
        .x_integer_bits(x_integer_bits),
        .input_valid(input_valid),
        .reciprocal(reciprocal),
        .output_valid(output_valid)
    );

    // Test variables
    integer idx;
    reg [31:0] test_inputs [0:9];
    reg [31:0] expected_outputs [0:9];
    reg [3:0] integer_bits [0:9];
    integer passed_tests;
    integer failed_tests;
    reg [31:0] diff; // To calculate the difference

    // Parameters for fixed-point format Q4.27
    parameter INTEGER_BITS = 4;          // Number of integer bits (excluding sign bit)
    parameter FRACTIONAL_BITS = 27;      // Number of fractional bits
    parameter TOTAL_BITS = 1 + INTEGER_BITS + FRACTIONAL_BITS; // Total bits (1 sign bit + integer bits + fractional bits)

    // Maximum allowed error: 2^-9 in Q1.0.31 format
    parameter [31:0] MAX_ERROR = 32'h00400000; // 2^-9 * 2^31 = 0x00400000

    // Generate clock without using forever
    initial begin
        clk = 0;
        repeat (1000) #5 clk = ~clk; // Simulate enough cycles to complete all operations
    end

    // Reset signal
    initial begin
        rst = 0;
        #20;
        rst = 1;
    end

    // FSDB dump for waveform viewing (optional)
    initial begin
        $fsdbDumpfile("verdi.fsdb");
        $fsdbDumpvars(0, reciprocal_over_1_tb, "+all");
    end

    // Initialize inputs and expected outputs
    initial begin
    // Initialize counters
    passed_tests = 0;
    failed_tests = 0;

    // Define test cases
    // First five test cases in Q4.27 format
    test_inputs[0] = 32'b0_0001_010011001100110011001100110; // 1.3 in Q4.27
    expected_outputs[0] = 32'h623DDC26; // ~0.7692307692307692 in Q1.0.31
    integer_bits[0] = 4;

    test_inputs[1] = 32'b0_0001_100000000000000000000000000; // 1.5 in Q4.27
    expected_outputs[1] = 32'h55555555; // 0.6666666666666666 in Q1.0.31
    integer_bits[1] = 4;

    test_inputs[2] = 32'b0_0001_010000000000000000000000000; // 1.25 in Q4.27
    expected_outputs[2] = 32'h66666666; // 0.8 in Q1.0.31
    integer_bits[2] = 4;

    test_inputs[3] = 32'b0_0001_000110011001100110011001100; // 1.1 in Q4.27
    expected_outputs[3] = 32'h746E276B; // ~0.9090909091 in Q1.0.31
    integer_bits[3] = 4;

    test_inputs[4] = 32'b0_0001_111111111111111111111111111; // ~1.9999999 in Q4.27
    expected_outputs[4] = 32'h40000000; // 0.5 in Q1.0.31
    integer_bits[4] = 4;

    // Next five test cases in different formats
    // Q1.2.29 format
    test_inputs[5] = 32'b0_01_01000000000000000000000000000; // 1.25 in Q1.2.29
    expected_outputs[5] = 32'h66666666; // ~0.190476 in Q1.0.31
    integer_bits[5] = 2; // Q1.2.29, integer_bits = 2

    // Q1.3.28 format
    test_inputs[6] = 32'b0_011_1000000000000000000000000000; // 3.5 in Q1.3.28
    expected_outputs[6] = 32'h24924924; // ~0.0689655 in Q1.0.31
    integer_bits[6] = 3; // Q1.3.28, integer_bits = 3

    // Q1.1.30 format
    test_inputs[7] = 32'b0_0001_110000000000000000000000000; // 1.75 in Q1.4.27
    expected_outputs[7] = 32'h49249249; // ~0.57 in Q1.0.31
    integer_bits[7] = 4; // Q1.1.30, integer_bits = 1

    // Q1.2.29 format
    test_inputs[8] = 32'b0_11_11000000000000000000000000000; // 3.75 in Q1.2.29
    expected_outputs[8] = 32'h22222222; // ~0.129032258 in Q1.0.31
    integer_bits[8] = 2; // Q1.2.29, integer_bits = 2

    // Q1.3.28 format
    test_inputs[9] = 32'b0_111_0010000000000000000000000000; // 7.125 in Q1.3.28
    expected_outputs[9] = 32'b00010001111101001000111110000011; // ~0.140350877193 in Q1.0.31
    integer_bits[9] = 3; // Q1.3.28, integer_bits = 3
end

    // Apply inputs sequentially
    initial begin
        idx = 0;
        input_valid = 0;
        #30; // Ensure reset is complete

        while (idx < 10) begin
            @(negedge clk);
            // #1;
            x = test_inputs[idx];
            x_integer_bits = integer_bits[idx];
            input_valid = 1;
            // @(negedge clk);
            // input_valid = 0;
            idx = idx + 1;
        end
        @(negedge clk);
        input_valid = 0;
    end

    // Monitor output and compare results
    integer result_count = 0;

    always @(posedge clk) begin
        if (output_valid) begin
            // Calculate absolute difference
            if (reciprocal > expected_outputs[result_count])
                diff = reciprocal - expected_outputs[result_count];
            else
                diff = expected_outputs[result_count] - reciprocal;

            // Check if within error tolerance
            if (diff <= MAX_ERROR) begin
                $display("Test case %d: Passed.", result_count);
                passed_tests = passed_tests + 1;
            end else begin
                $display("Test case %d: Failed.", result_count);
                failed_tests = failed_tests + 1;
            end

            // Print input, expected, and received outputs
            $display("Input: %b", test_inputs[result_count]);
            $display("Expected Output: %b", expected_outputs[result_count]);
            $display("Received Output: %b", reciprocal);
            $display("Difference: %b (Hex: %h)", diff, diff);
            $display("-----------------------------------");

            result_count = result_count + 1;

            // Finish after all results are checked
            if (result_count == 10) begin
                $display("Test finished: %d tests passed, %d tests failed.", passed_tests, failed_tests);
                if(passed_tests == 10) begin
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
                    $display("Some tests failed. Q_Q");
                end
                $finish;
            end 
        end
    end


endmodule
