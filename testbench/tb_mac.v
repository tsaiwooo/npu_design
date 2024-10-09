module tb_mac();

    // mac Parameters
    parameter PERIOD      = 10;
    parameter MAX_MACS    = 64;
    parameter DATA_WIDTH  = 8;

    // mac Inputs
    reg   clk                                  = 0;
    reg   rst                                  = 0;
    reg   [10:0]   num_macs_i =                   0;           
    reg   valid_in                             = 0;
    reg   [DATA_WIDTH-1:0]  data [MAX_MACS-1:0];
    reg   [DATA_WIDTH-1:0]  weight [MAX_MACS-1:0];

    // Flattened versions of the arrays for connection to the DUT as reg
    reg [MAX_MACS*DATA_WIDTH-1:0] data_flat;
    reg [MAX_MACS*DATA_WIDTH-1:0] weight_flat;

    // mac Outputs
    wire  [2*DATA_WIDTH-1:0]  mac_out;
    wire  valid_out;

    // Pass/Fail counters
    integer pass_count = 0;
    integer fail_count = 0;

    // Clock generation
    initial begin
        forever #(PERIOD/2) clk = ~clk;
    end

    // Reset logic
    initial begin
        rst = 1;
        #(PERIOD*3);
        rst = 0;
    end

    initial begin
        // FSDB file name
        $fsdbDumpfile("verdi.fsdb");
        
        // Dump all variables in the design hierarchy (from tb_mac)
        $fsdbDumpvars(0, tb_mac, "+all");
    end

    // Instantiate the MAC module
    mac #(
        .MAX_MACS   ( MAX_MACS   ),
        .DATA_WIDTH ( DATA_WIDTH ))
    u_mac (
        .clk                     ( clk                                       ),
        .rst                     ( rst                                       ),
        .num_macs_i              ( num_macs_i                                ),
        .valid_in                ( valid_in                                  ),
        .data                    ( data_flat                                 ),
        .weight                  ( weight_flat                               ),
        .mac_out                 ( mac_out                                   ),
        .valid_out               ( valid_out                                 )
    );

    // Task to test a specific number of MACs
    task test_mac;
        input [6:0] macs;  // Number of MACs to test

        integer cycle_count = 0;
        integer start_cycle = 0;
        integer end_cycle = 0;
        reg [2*DATA_WIDTH-1:0] expected_result = 0;
        reg start_flag = 0;  // A flag to ensure start_cycle is only set once
        reg result_checked = 0;  // A flag to ensure the result is only checked once
        integer i;

        begin
            // Assign values for num_macs_i
            num_macs_i = macs;
            $display("Testing num_macs_i = %0d", macs);

            // Initialize data and weight
            for (i = 0; i < MAX_MACS; i = i + 1) begin
                data[i] = i + 1;            // Example data values: 1, 2, 3, ..., 32
                weight[i] = MAX_MACS - i;   // Example weight values: 32, 31, 30, ..., 1
                data_flat[i*DATA_WIDTH +: DATA_WIDTH] = data[i];
                weight_flat[i*DATA_WIDTH +: DATA_WIDTH] = weight[i];
            end

            // Set valid_in to 1 to start processing
            valid_in = 1;
            
            // Wait for result to be computed
            cycle_count = 0;
            start_flag = 0;
            result_checked = 0;
            while (!valid_out && !result_checked) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                if (valid_in && !start_flag) begin
                    start_cycle = cycle_count;
                    start_flag = 1;
                end
                if (valid_out && !result_checked) begin
                    end_cycle = cycle_count;
                    expected_result = 0;
                    for (i = 0; i < macs; i = i + 1) begin
                        expected_result += data[i] * weight[i];
                    end

                    // Display results
                    $display("Total cycles used: %0d", end_cycle - start_cycle);
                    $display("Calculated expected_result = %0d, num_macs_i = %d", expected_result, num_macs_i);
                    if (mac_out == expected_result) begin
                        $display("Test passed. MAC result is correct: %0d", mac_out);
                        pass_count = pass_count + 1;  // Increment pass counter
                    end else begin
                        $display("Test failed. MAC result is incorrect. Expected: %0d, Got: %0d", expected_result, mac_out);
                        fail_count = fail_count + 1;  // Increment fail counter
                        $finish;
                    end
                    result_checked = 1;
                end
            end

            // Set valid_in to 0 after result is checked
            valid_in = 0;
            #(PERIOD * 10);
        end
    endtask

    // Test all cases from 1 to 32 MACs
    initial begin
        integer j;
        // Wait for reset
        #(PERIOD * 10);

        // Loop over 1 to 32 MACs and call the test task
        for (j = 1; j <= 64; j = j + 1) begin
            test_mac(j);
        end

        // Display the number of passed and failed tests
        $display("Total Passed: %0d, Total Failed: %0d", pass_count, fail_count);

        // If all tests passed, print "All tests passed"
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
            $display("Some tests failed.");
        end

        // End the simulation
        $finish;
    end

endmodule
