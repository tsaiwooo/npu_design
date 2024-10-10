//~ `New testbench
`timescale  1ns / 1ps

module tb_sram_dp();

// sram_dp Parameters
parameter PERIOD              = 10                   ;
parameter DATA_WIDTH          = 8                    ;
parameter N_ENTRIES           = 4096                 ;
parameter ADDRW               = $clog2(N_ENTRIES)    ;
parameter MAX_CHANNELS        = 64                   ;
parameter NUM_CHANNELS_WIDTH  = $clog2(MAX_CHANNELS+1);

// sram_dp Inputs
reg   clk1_i                               = 0 ;
reg   en1_i                                = 0 ;
reg   we1_i                                = 0 ;
reg   [NUM_CHANNELS_WIDTH-1:0]  num_channels1_i = 0 ;
reg   [ADDRW*MAX_CHANNELS-1 : 0]  addr1_i  = 0 ;
reg   [DATA_WIDTH*MAX_CHANNELS-1 : 0]  data1_i = 0 ;
reg   clk2_i                               = 0 ;
reg   en2_i                                = 0 ;
reg   we2_i                                = 0 ;
reg   [NUM_CHANNELS_WIDTH-1:0]  num_channels2_i = 0 ;
reg   [ADDRW*MAX_CHANNELS-1 : 0]  addr2_i  = 0 ;
reg   [DATA_WIDTH*MAX_CHANNELS-1 : 0]  data2_i = 0 ;

// sram_dp Outputs
wire  [DATA_WIDTH*MAX_CHANNELS-1 : 0]  data1_o ;
wire  ready1_o                             ;
wire  [DATA_WIDTH*MAX_CHANNELS-1 : 0]  data2_o ;
wire  ready2_o                             ;

// Clock generation
initial begin
    forever #(PERIOD/2) clk1_i = ~clk1_i;
end

initial begin
    forever #(PERIOD/2) clk2_i = ~clk2_i;
end

// Instantiate the SRAM module
sram_dp #(
    .DATA_WIDTH         ( DATA_WIDTH         ),
    .N_ENTRIES          ( N_ENTRIES          ),
    .ADDRW              ( ADDRW              ),
    .MAX_CHANNELS       ( MAX_CHANNELS       ),
    .NUM_CHANNELS_WIDTH ( NUM_CHANNELS_WIDTH )
) u_sram_dp (
    .clk1_i                  ( clk1_i                                           ),
    .en1_i                   ( en1_i                                            ),
    .we1_i                   ( we1_i                                            ),
    .num_channels1_i         ( num_channels1_i                                  ),
    .addr1_i                 ( addr1_i                                          ),
    .data1_i                 ( data1_i                                          ),
    .clk2_i                  ( clk2_i                                           ),
    .en2_i                   ( en2_i                                            ),
    .we2_i                   ( we2_i                                            ),
    .num_channels2_i         ( num_channels2_i                                  ),
    .addr2_i                 ( addr2_i                                          ),
    .data2_i                 ( data2_i                                          ),
    .data1_o                 ( data1_o                                          ),
    .ready1_o                ( ready1_o                                         ),
    .data2_o                 ( data2_o                                          ),
    .ready2_o                ( ready2_o                                         )
);

integer i;
integer pass = 0;
integer rand_value;
reg [DATA_WIDTH*MAX_CHANNELS-1:0] write_data_mem [511:0]; // Buffer to store written data for 512 entries


// Test data
initial begin
    // Reset system
    en1_i = 0;
    we1_i = 0;
    num_channels1_i = 0;
    addr1_i = 0;
    data1_i = 0;
    en2_i = 0;
    we2_i = 0;
    num_channels2_i = 0;
    addr2_i = 0;
    data2_i = 0;

    // Wait for the system to initialize
    #(PERIOD*2);

    // Step 1: Write first 64 entries in a single operation
    @(posedge clk1_i);
    en1_i = 1;
    we1_i = 1;
    num_channels1_i = 64;  // Write 64 channels

    // Write consecutive addresses and random data to SRAM
    addr1_i = 0;
    data1_i = 0;
    for (integer j = 0; j < 64; j = j + 1) begin
        addr1_i[ADDRW*(j+1)-1 -: ADDRW] = j;  // Consecutive addresses
        rand_value = $urandom_range(255, 0);  // Random data
        data1_i[DATA_WIDTH*(j+1)-1 -: DATA_WIDTH] = rand_value;
        write_data_mem[j] = rand_value; // Store the written data for later verification
    end

    @(posedge clk1_i);
    en1_i = 0;
    we1_i = 0;

    // Wait for write completion
    @(posedge clk1_i);

    // Step 2: Write additional entries while reading the previous ones in parallel
    for (i = 64; i < 512; i = i + 64) begin
        // Write operation (64 channels per cycle)
        @(posedge clk1_i);
        en1_i = 1;
        we1_i = 1;
        num_channels1_i = 64;  // Write 64 channels

        addr1_i = 0;
        data1_i = 0;
        for (integer j = 0; j < 64; j = j + 1) begin
            addr1_i[ADDRW*(j+1)-1 -: ADDRW] = i + j;  // Write to consecutive addresses
            rand_value = $urandom_range(255, 0);
            data1_i[DATA_WIDTH*(j+1)-1 -: DATA_WIDTH] = rand_value;
            write_data_mem[i + j] = rand_value; // Store written data for later checking
        end

        // Parallel read operation (64 channels per cycle)
        en2_i = 1;
        we2_i = 0;
        num_channels2_i = 64;  // Read 64 channels

        addr2_i = 0;
        for (integer k = 0; k < 64; k = k + 1) begin
            addr2_i[ADDRW*(k+1)-1 -: ADDRW] = i - 64 + k;  // Read from addresses written earlier
        end

        @(posedge clk2_i);
        if (ready2_o) begin
            // Compare the read data with the expected values
            for (integer l = 0; l < 64; l = l + 1) begin
                if (data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH] !== write_data_mem[i - 64 + l]) begin
                    $display("Test failed at addr %0d: expected %0d, got %0d", i-64+l, write_data_mem[i-64+l], data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH]);
                    $finish;
                end else begin
                    $display("Test passed at addr %0d: expected %0d, got %0d", i-64+l, write_data_mem[i-64+l], data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH]);
                    pass = pass + 1;
                end
            end
        end

        @(posedge clk1_i);
        en1_i = 0;

        @(posedge clk2_i);
        en2_i = 0;
    end

    $display("Total passes: %0d", pass);
    
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
    $finish;
end

endmodule
