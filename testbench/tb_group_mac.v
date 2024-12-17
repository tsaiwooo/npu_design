`timescale 1ns / 1ps

module tb_mac;

// mac Parameters
parameter PERIOD             = 10;
parameter MAX_MACS           = 64;
parameter DATA_WIDTH         = 8; // Data width is 8 bits
parameter MAX_GROUPS         = 8;
parameter MAC_BIT_PER_GROUP  = 6;

reg   clk  = 0 ;
reg   rst  = 0 ;
reg   [$clog2(MAX_GROUPS+1)-1:0] num_groups = 0;
reg   [MAX_GROUPS * MAC_BIT_PER_GROUP -1:0] num_macs_i = 0;
reg   valid_in = 0;
reg   signed [MAX_MACS*DATA_WIDTH-1:0] data = 0;
reg   signed [MAX_MACS*DATA_WIDTH-1:0] weight = 0;

wire [MAX_GROUPS*4*DATA_WIDTH-1:0] mac_out;
wire valid_out;

integer i, group_idx, start_idx;
integer test_count = 0;
integer output_count = 0;
integer total_tests = 10;
reg overall_pass_test;

reg signed [4*DATA_WIDTH-1:0] all_golden_mac_out [0:1023][0:MAX_GROUPS-1];

// Instantiate the DUT
mac #(
    .MAX_MACS          ( MAX_MACS          ),
    .DATA_WIDTH        ( DATA_WIDTH        ),
    .MAX_GROUPS        ( MAX_GROUPS        ),
    .MAC_BIT_PER_GROUP ( MAC_BIT_PER_GROUP )
) u_mac (
    .clk        ( clk        ),
    .rst        ( rst        ),
    .num_groups ( num_groups ),
    .num_macs_i ( num_macs_i ),
    .valid_in   ( valid_in   ),
    .data       ( data       ),
    .weight     ( weight     ),
    .mac_out    ( mac_out    ),
    .valid_out  ( valid_out  )
);

// 產生並計算golden result的task
task generate_test_and_golden;
    output [$clog2(MAX_GROUPS+1)-1:0] out_num_groups;
    output [MAX_GROUPS * MAC_BIT_PER_GROUP -1:0] out_num_macs_i;
    output reg signed [MAX_MACS*DATA_WIDTH-1:0] out_data;
    output reg signed [MAX_MACS*DATA_WIDTH-1:0] out_weight;
    output reg signed [4*DATA_WIDTH-1:0] out_golden [0:MAX_GROUPS-1];

    integer g, mac_c, idx;
begin
    out_num_groups = $urandom_range(2,8);
    out_num_macs_i = 0;

    for (g = 0; g < out_num_groups; g = g + 1) begin
        out_num_macs_i[g*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP] = $urandom_range(1,8);
    end

    out_data = 0;
    out_weight = 0;
    for (mac_c = 0; mac_c < MAX_MACS; mac_c = mac_c + 1) begin
        out_data[mac_c*DATA_WIDTH +: DATA_WIDTH] = $urandom % 256;
        out_weight[mac_c*DATA_WIDTH +: DATA_WIDTH] = $urandom % 256;
    end

    // 計算 golden result 只迴圈到 out_num_groups
    idx = 0;
    for (g = 0; g < out_num_groups; g = g + 1) begin
        integer count_per_group;
        integer k;
        out_golden[g] = 0;
        count_per_group = out_num_macs_i[g*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP];
        for (k = 0; k < count_per_group; k = k + 1) begin
            out_golden[g] = out_golden[g] + $signed(out_data[(idx+k)*DATA_WIDTH +: DATA_WIDTH]) * 
                                            $signed(out_weight[(idx+k)*DATA_WIDTH +: DATA_WIDTH]);
        end
        idx += count_per_group;
    end

    // 對未使用的 group (大於 out_num_groups) 清0
    for (g = out_num_groups; g < MAX_GROUPS; g = g + 1) begin
        out_golden[g] = 0;
    end
end
endtask

// Clock generation
initial begin
    forever #(PERIOD/2) clk = ~clk;
end

// Reset
initial begin
    rst = 0;
    #20;
    rst = 1;
end

// FSDB dump
initial begin
    $fsdbDumpfile("verdi.fsdb");
    $fsdbDumpvars(0, tb_mac, "+all");
end

initial begin
    overall_pass_test = 1;
    @(posedge rst);

    // 連續送出 total_tests 筆資料
    for (i = 0; i < total_tests; i = i + 1) begin
        reg [$clog2(MAX_GROUPS+1)-1:0] t_num_groups;
        reg [MAX_GROUPS * MAC_BIT_PER_GROUP -1:0] t_num_macs_i;
        reg signed [MAX_MACS*DATA_WIDTH-1:0] t_data, t_weight;
        reg signed [4*DATA_WIDTH-1:0] t_golden [0:MAX_GROUPS-1];

        // 產生一筆測試資料與 golden
        generate_test_and_golden(t_num_groups, t_num_macs_i, t_data, t_weight, t_golden);

        // 將 golden result 存入 all_golden_mac_out[test_count]
        for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
            all_golden_mac_out[test_count][group_idx] = t_golden[group_idx];
        end

        // 將資料送入 DUT
        @(negedge clk);
        num_groups <= t_num_groups;
        num_macs_i <= t_num_macs_i;
        data       <= t_data;
        weight     <= t_weight;
        valid_in   <= 1;

        @(negedge clk);
        valid_in   <= 0;

        test_count = test_count + 1;
        #20; // 不等待valid_out, 繼續下一筆
    end

    // 等 pipeline flush
    repeat(20) @(negedge clk);

    if (overall_pass_test) begin
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
        $display("All test cases passed!");
    end else begin
        $display("Some test cases failed.");
    end

    $finish;
end

// 當 valid_out=1 時，比對輸出
integer g;
always @(posedge clk) begin
    if (rst && valid_out) begin
        // 根據當時的 num_groups (已經latched在DUT內) 來比對對應的 group數量
        // 注意: num_groups 在這裡是當下DUT處理的值，可在DUT中設計將處理中之num_groups寄存起來供輸出參考，
        // 或在testbench中使用FIFO來記錄每筆輸入資料的num_groups。
        // 為簡化，這裡假設我們知道 output_count 對應的 t_num_groups (可在送出時也記錄下每次的 t_num_groups)
        
        // 此處示範用法: 假設我們在一個陣列中也存下了對應 input 的 t_num_groups
        // 您需要在輸入時同步記錄 t_num_groups，這裡僅示範概念。

        reg [$clog2(MAX_GROUPS+1)-1:0] current_num_groups;
        
        // 您需要一個陣列來記錄每次輸入時的num_groups:
        // reg [$clog2(MAX_GROUPS+1)-1:0] test_num_groups [0:1023];
        // 在送資料時：test_num_groups[test_count] = t_num_groups;
        
        // 假設我們有記錄：
        // current_num_groups = test_num_groups[output_count];

        // 為了示範，現在假設 current_num_groups = num_groups; 
        // (實務上 pipeline 中可能需要另存 num_groups，這取決於DUT設計)
        current_num_groups = num_groups;

        for (g = 0; g < current_num_groups; g = g + 1) begin
            if ($signed(mac_out[g*4*DATA_WIDTH +: 4*DATA_WIDTH]) !== all_golden_mac_out[output_count][g]) begin
                $display("Output %d failed at group %d: Expected %d, Got %d", 
                          output_count, g, 
                          all_golden_mac_out[output_count][g], 
                          $signed(mac_out[g*4*DATA_WIDTH +: 4*DATA_WIDTH]));
                overall_pass_test = 0;
            end else begin
                $display("Output %d passed at group %d: Expected %d, Got %d", 
                          output_count, g,
                          all_golden_mac_out[output_count][g],
                          $signed(mac_out[g*4*DATA_WIDTH +: 4*DATA_WIDTH]));
            end
        end
        output_count = output_count + 1;
    end
end

endmodule
