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
integer write_idx = 0;
reg [7:0] tb_data[2100:0];

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

    // Loop through 1 to 64 channels
    for (i = 1; i <= MAX_CHANNELS; i = i + 1) begin
        // Write operation
        @(posedge clk1_i);
        en1_i = 1;
        we1_i = 1;
        num_channels1_i = i;  // Write i channels

        // Write addresses and data
        addr1_i = 0;
        data1_i = 0;
        for (integer j = 0; j < i; j = j + 1) begin
            addr1_i[ADDRW*(j+1)-1 -: ADDRW] = j;  // Writing to consecutive addresses
            rand_value = $urandom_range(255,0);
            // tb_data[wrire_idx] = rand_value;
            // $display("Random value :%0d",rand_value);
            data1_i[DATA_WIDTH*(j+1)-1 -: DATA_WIDTH] = rand_value;  // Data = address + 1
            // write_idx = wrire_idx + 1;
        end

        @(posedge clk1_i);
        en1_i = 0;
        we1_i = 0;

        // Wait for write completion
        @(posedge clk1_i);

        // Read operation
        @(posedge clk2_i);
        en2_i = 1;
        we2_i = 0;
        num_channels2_i = i;  // Read i channels

        addr2_i = 0;
        for (integer k = 0; k < i; k = k + 1) begin
            addr2_i[ADDRW*(k+1)-1 -: ADDRW] = k;  // Reading from the same consecutive addresses
        end

        // Wait for the data to be available
        @(posedge clk2_i);
        if (ready2_o) begin
            // Compare the read data with the expected values
            for (integer l = 0; l < i; l = l + 1) begin
                // if (data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH] !== l + 1) begin
                if (data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH] !== data1_i[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH]) begin
                    $display("Test failed for channel %0d: expected %0d, got %0d", l, data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH], data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH]);
                    $finish;
                end else begin
                    $display("Test passed for channel %0d: expected %0d, got %0d", l, data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH], data2_o[DATA_WIDTH*(l+1)-1 -: DATA_WIDTH]);
                    pass = pass + 1;
                end
            end
        end

        @(posedge clk2_i);
        en2_i = 0;
    end
    
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
