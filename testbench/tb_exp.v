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
        // test_data[0] = 32'hFF333333;  // -0.1 in Q4.27
        // golden_results[0] = 32'h73E0B69D;  // ~0.905 in Q0.31

        // test_data[1] = 32'hFE666666;  // -0.2 in Q4.27
        // golden_results[1] = 32'h68DB8BAC;  // ~0.819 in Q0.31

        // test_data[2] = 32'hFD99999A;  // -0.3 in Q4.27
        // golden_results[2] = 32'h5F4FB460;  // ~0.741 in Q0.31

        // test_data[3] = 32'hFCCCCCCE;  // -0.4 in Q4.27
        // golden_results[3] = 32'h55E63A3E;  // ~0.670 in Q0.31

        // test_data[4] = 32'hFBFFFFFF;  // -0.5 in Q4.27
        // golden_results[4] = 32'h4DA33613;  // ~0.607 in Q0.31

        // test_data[5] = 32'hF999999A;  // -0.6 in Q4.27
        // golden_results[5] = 32'h45B79F6D;  // ~0.548 in Q0.31

        // test_data[6] = 32'hF6666666;  // -0.7 in Q4.27
        // golden_results[6] = 32'h3F8EFD5B;  // ~0.497 in Q0.31

        // test_data[7] = 32'hF3333332;  // -0.8 in Q4.27
        // golden_results[7] = 32'h394E1E5B;  // ~0.449 in Q0.31
        
        // test_data[8] = 32'hF0000000;  // -0.9 in Q4.27
        // golden_results[8] = 32'h33C2F4B2;  // ~0.406 in Q0.31

        // test_data[9] = 32'hEE666666;  // -1 in Q4.27
        // golden_results[9] = 32'h2E5F2A3C;  // ~0.368 in Q0.31

        test_data[0] = 32'hFF333333;  //  in Q4.27
        golden_results[0] = 32'h73E0B69D;  // ~0.905 in Q0.31

        test_data[1] = 32'hffa12300;  // -0.04633 in Q4.27
        golden_results[1] = 32'h7a34cd81;  // ~0.819 in Q0.31

        test_data[2] = 32'hfee36900;  // in Q4.27
        golden_results[2] = 32'h6f64c6a7;  // ~0.741 in Q0.31

        test_data[3] = 32'hff12d780;  // in Q4.27
        golden_results[3] = 32'h7200ee6c;  // ~0.670 in Q0.31

        test_data[4] = 32'hfe551d80;  // -0.2085 in Q4.27
        golden_results[4] = 32'h67eab2b0;  // ~0.607 in Q0.31

        test_data[5] = 32'hffa12300;  // -0.04633 in Q4.27
        golden_results[5] = 32'h7a34cd81;  // ~0.548 in Q0.31

        test_data[6] = 32'hfe25af00;  // -0.2313 in Q4.27
        golden_results[6] = 32'h6589a986;  // ~0.497 in Q0.31

        test_data[7] = 32'h0;  // in Q4.27
        golden_results[7] = 32'h7fffffff;  // ~0.449 in Q0.31
        
        test_data[8] = 32'hffd09180;  // -0.023166 in Q4.27
        golden_results[8] = 32'h7d11cfce;  // ~0.406 in Q0.31

        test_data[9] = 32'hfee36900;  // in Q4.27
        golden_results[9] = 32'h6f64c6a7;  // ~0.368 in Q0.31
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
