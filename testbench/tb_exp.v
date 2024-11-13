`timescale 1ns / 1ps

module tb_exp;
    // Parameters
    parameter CLK_PERIOD = 10;
    parameter TEST_COUNT = 10;
    parameter TOLERANCE = 32'd21474836;  // Allowable error for Q0.31 (~10^-2)
    
    // Signals
    reg clk;
    reg rst;
    reg [31:0] x;
    reg [3:0] integer_bits;
    reg input_valid;
    wire [31:0] exp_x;
    wire output_valid;
    
    // Test vectors
    reg [31:0] test_data [0:TEST_COUNT-1];
    reg [31:0] golden_results [0:TEST_COUNT-1];
    integer error_count;
    integer i, output_index;
    
    // Instantiate DUT
    exp_pipeline dut (
        .clk(clk),
        .rst(rst),
        .x(x),
        .integer_bits(integer_bits),
        .input_valid(input_valid),
        .exp_x(exp_x),
        .output_valid(output_valid)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        // FSDB file name
        $fsdbDumpfile("verdi.fsdb");
        
        // Dump all variables in the design hierarchy (from tb_mac)
        $fsdbDumpvars(0, tb_exp, "+all");
    end
    
    // Initialize test data
    initial begin
        test_data[0] = 32'h80CCCCCD;  // -0.1 in Q4.27
        golden_results[0] = 32'h73E0B69D;  // ~0.905 in Q0.31

        test_data[1] = 32'h8199999A;  // -0.2 in Q4.27
        golden_results[1] = 32'h68DB8BAC;  // ~0.819 in Q0.31

        test_data[2] = 32'h82666666;  // -0.3 in Q4.27
        golden_results[2] = 32'h5F4FB460;  // ~0.741 in Q0.31

        test_data[3] = 32'h83333333;  // -0.4 in Q4.27
        golden_results[3] = 32'h55E63A3E;  // ~0.670 in Q0.31

        test_data[4] = 32'h84000000;  // -0.5 in Q4.27
        golden_results[4] = 32'h4DA33613;  // ~0.607 in Q0.31

        test_data[5] = 32'h84CCCCCC;  // -0.6 in Q4.27
        golden_results[5] = 32'h45B79F6D;  // ~0.548 in Q0.31

        test_data[6] = 32'h85999999;  // -0.7 in Q4.27
        golden_results[6] = 32'h3F8EFD5B;  // ~0.497 in Q0.31

        test_data[7] = 32'h86666666;  // -0.8 in Q4.27
        golden_results[7] = 32'h394E1E5B;  // ~0.449 in Q0.31
        
        test_data[8] = 32'h87333333;  // -0.9 in Q4.27
        golden_results[8] = 32'h33C2F4B2;  // ~0.406 in Q0.31

        test_data[9] = 32'h88000000;  // -1 in Q4.27
        golden_results[9] = 32'h2E5F2A3C;  // ~0.368 in Q0.31

        // test_data[10] = 32'h8899999A;  // -1.1 in Q4.27
        // golden_results[10] = 32'h294287F4;  // ~0.332 in Q0.31

        // test_data[11] = 32'h89333333;  // -1.2 in Q4.27
        // golden_results[11] = 32'h244B2E35;  // ~0.301 in Q0.31

        // test_data[12] = 32'h8A000000;  // -1.5 in Q4.27
        // golden_results[12] = 32'h1A54E9F9;  // ~0.223 in Q0.31

        // test_data[13] = 32'h8ACCCCCD;  // -1.6 in Q4.27
        // golden_results[13] = 32'h167F3B27;  // ~0.201 in Q0.31

        // test_data[14] = 32'h8B666666;  // -1.7 in Q4.27
        // golden_results[14] = 32'h12B354A6;  // ~0.183 in Q0.31
    end
    
    // Test procedure
    initial begin
        // Initialize
        rst = 0;
        input_valid = 0;
        integer_bits = 4'd4;  // Q4.27 format
        error_count = 0;
        output_index = 0;
        
        // Reset
        #(CLK_PERIOD*2);
        rst = 1;
        #(CLK_PERIOD);
        
        // Send each test vector with one cycle input_valid signal for each
        for (i = 0; i < TEST_COUNT; i = i + 1) begin
            // Apply input and set input_valid high for one cycle
            @(negedge clk);
            input_valid = 1;
            x = test_data[i];
            $display("Sending test vector %0d: %h", i, test_data[i]);

            // Lower input_valid on the next cycle
            // @(posedge clk);
            // input_valid = 0;
        end
        @(negedge clk);
        input_valid = 0;
    end

    always @(posedge clk) begin
        if (output_valid) begin
            $display("Received output %0d: %h", output_index, exp_x);
            
            // Compare exp_x with golden_results within tolerance
            if (exp_x > golden_results[output_index]) begin
                if ((exp_x - golden_results[output_index]) <= TOLERANCE) begin
                    $display("Vector %0d passed within tolerance! golden val = %h, got val = %h", output_index, golden_results[output_index], exp_x);
                end else begin
                    $display("Error at vector %0d:", output_index);
                    $display("Expected: %h", golden_results[output_index]);
                    $display("Got     : %h", exp_x);
                    error_count = error_count + 1;
                end
            end else begin
                if ((golden_results[output_index] - exp_x) <= TOLERANCE) begin
                    $display("Vector %0d passed within tolerance! golden val = %h, got val = %h", output_index, golden_results[output_index], exp_x);
                end else begin
                    $display("Error at vector %0d:", output_index);
                    $display("Expected: %h", golden_results[output_index]);
                    $display("Got     : %h", exp_x);
                    error_count = error_count + 1;
                end
            end
            
            output_index = output_index + 1;
            
            // Check if all outputs have been verified
            if (output_index == TEST_COUNT) begin
                // Print final results
                if (error_count == 0) begin
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
                    $display("\nTEST PASSED: All %0d test vectors passed within tolerance!", TEST_COUNT);
                end else begin
                    $display("\nTEST FAILED: %0d out of %0d test vectors failed!", error_count, TEST_COUNT);
                end
                $finish;
            end
        end
    end
endmodule
