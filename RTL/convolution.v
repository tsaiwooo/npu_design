// GEMM要實體化mac, 從convolution拿到input data且回傳data
// convolution需要做的事情是給sram_controller address, 然後拿資料
// 假如kernel是3*3 那麼我計算時會盡量等填滿pe才開始進行運算, 也就是說等64/(3*3)組data排好後才啟動mac做運算

// 從sram拿資料可以改進
// 1. 因為會重複reuse到data, 所以一開始計算好可能會計算到的groups
// 2. 同一個row可以一次拿取, 然後再拿取下一個row
// 3. 例如kernel 3*3, 我需要7組data, 但是我可以一次拿取8個data, 我可以先拿完一個row
//    convolution再來排順序, ex: 
// ***** 0,1,2,3,4,5,6,7 ***** 這是data拿到的資料 
// ***** a,b,c,d,e,d,f,g ***** 這是weight拿到的資料
// ***** 0,1,2, 1,2,3 , 2,3,4 , 3,4,5 , 4,5,6 , 5,6,7 , 6,7,8 , 7,8,9  *****
// ***** a,b,c, b,c,d , c,d,e , d,e,f , e,d,f , d,f,g , f,g,h , g,h,i  *****
`timescale 1ns / 1ps
`include "params.vh"

module convolution #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter MAX_ADDR_WIDTH = 18,
    parameter DATA_WIDTH = 8,
    parameter QUANT_WIDTH = 32,
    parameter MAC_BIT_PER_GROUP = 6,
    parameter MAX_GROUPS = 8,
    parameter MAX_ITER = 16
)
(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   en,
    // input metadata
    input  wire [ADDR_WIDTH-1:0]  img_row,
    input  wire [ADDR_WIDTH-1:0]  img_col,
    input  wire [ADDR_WIDTH-1:0]  ker_row,
    input  wire [ADDR_WIDTH-1:0]  ker_col,
    // img and kernel data from sram
    input  wire [SRAM_WIDTH_O-1:0]  data_in,
    input  wire [SRAM_WIDTH_O-1:0]  weight_in,
    // output signal control that mac data is ready
    output wire                   mac_data_ready_o,
    output reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_o,
    output reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_o,
    // output number of groups
    output wire [$clog2(MAX_GROUPS+1) -1:0]             num_groups_o,
    // output number macs of each group
    output wire [MAX_GROUPS * MAC_BIT_PER_GROUP - 1:0] num_macs_o,
    // input mac_out data from mac
    // input wire signed [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out,
    // output mac_out data from mac to sram_controller to store result because of multiple outputs
    output signed [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out_to_sram,
    // output image metadata
    output reg [ADDR_WIDTH-1:0]  conv_row,
    output reg [ADDR_WIDTH-1:0]  conv_col,
    output reg [ADDR_WIDTH-1:0]  for_conv_row,
    output reg [ADDR_WIDTH-1:0]  for_conv_col,
    // output weight idx metadata
    output [MAX_ADDR_WIDTH-1:0]  weight_idx_o
    // output reg [ADDR_WIDTH-1:0]  idx1_out
);
    // mac number of each group
    wire [6:0] macs_of_group;
    assign macs_of_group = ker_col * ker_row;

    reg en_delay;
    
    reg [ADDR_WIDTH-1:0] for_conv_row_delay;
    reg [ADDR_WIDTH-1:0] for_conv_col_delay;

    wire [6:0] shift_amount;
    wire [6:0] nums_input;
    assign shift_amount = $clog2(DATA_WIDTH); // 3
    assign nums_input = SRAM_WIDTH_O >> shift_amount; // 64 / 2^3, 最多一次能從sram取得的data數量

    wire [$clog2(MAX_MACS):0] total_macs;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_o;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_o;

    assign total_macs = ker_row * ker_col;
    // mac data ready
    reg mac_valid_in;
    assign mac_data_ready_o = mac_valid_in;

    wire [ADDR_WIDTH-1:0] out_row;
    wire [ADDR_WIDTH-1:0] out_col;
    assign out_row = img_row - ker_row + 1;
    assign out_col = img_col - ker_col + 1;

    // control output weight idx
    reg [MAX_ADDR_WIDTH-1:0] weight_idx;
    reg [MAX_ADDR_WIDTH-1:0] weight_idx_delay;
    assign weight_idx_o = weight_idx;
    // 計算每次有多少個group
    reg [2:0] num_groups_reg; 
    reg [2:0] groups;
    reg [7:0] remaining;
    reg [MAX_GROUPS * MAC_BIT_PER_GROUP - 1:0] num_macs_reg_all;
    assign num_groups_o = num_groups_reg;
    assign num_macs_o = num_macs_reg_all;

    // 一次可以取8個data, 其中最多可以有8 - ker_col + 1個group
    wire [2:0] groups_of_eight;
    assign groups_of_eight = MAX_GROUPS - ker_col + 1;

    integer i;
    always @(*)begin
        groups = 0;
        remaining =  64;

        for_loop: for (i = 0; i < MAX_ITER; i = i + 1)  begin 
            if (remaining >= total_macs) begin
                groups = groups + 1;
                remaining = remaining - total_macs;
            end else begin
                disable for_loop; // 結束循環
            end
        end

        if(conv_col + groups >= out_col)begin
            num_groups_reg = (groups_of_eight < groups)? groups_of_eight : out_col - conv_col;
        end else begin
            num_groups_reg = (groups_of_eight < groups)? groups_of_eight : groups;
        end
    end

    always @(*) begin
        integer g;
        num_macs_reg_all = {MAX_GROUPS * MAC_BIT_PER_GROUP{1'b0}};
        for (g = 0; g < MAX_GROUPS; g = g + 1) begin
            if (g < num_groups_reg) begin
                // 這組會被使用，寫入 macs_of_group
                // macs_of_group 是一個7 bits數值(最大64)，MAC_BIT_PER_GROUP=6可能不夠表示大於63的值，
                // 但在您的前提中macs_of_group應小於等於64，我們假設合適。
                // 若 macs_of_group <= 64，可用6 bits表達，如有需要請擴大MAC_BIT_PER_GROUP。
                num_macs_reg_all[g*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP] = macs_of_group[MAC_BIT_PER_GROUP-1:0];
            end else begin
                // 不使用的 group 填0
                num_macs_reg_all[g*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP] = {MAC_BIT_PER_GROUP{1'b0}};
            end
        end
    end

    always @(posedge clk) begin
        en_delay <= en;
    end

    // control convolution index
    always @(posedge clk) begin
        if (!rst) begin
            conv_col <= 0;
        end else if(conv_col == out_col - 1 && conv_row == out_row - 1  && mac_valid_in) begin
            conv_col <= 0;
        end else if (en_delay && for_conv_row == (ker_row-1)) begin
            // if (conv_col < out_col -1) begin
            //     conv_col <= conv_col + 1;  // Hold current value
            // end else begin
            //     conv_col <= 0;
            // end
            if(conv_col + num_groups_reg < out_col)begin
                conv_col <= conv_col + num_groups_reg; 
            end else begin
                conv_col <= 0;
            end
        end 
    end

    // conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            conv_row <= 0;
        end else if(conv_col >= out_col - 1 && conv_row >= out_row - 1 && mac_valid_in) begin
            conv_row <= 0; 
        end else if (en_delay && for_conv_row == (ker_row-1)) begin
            // if (conv_col < out_col - 1) begin
            //     conv_row <= conv_row;  // Hold current value
            // end else begin
            //     conv_row <= conv_row + 1;
            // end
            if(conv_col < out_col - num_groups_reg)begin
                conv_row <= conv_row; 
            end else begin
                conv_row <= conv_row + 1;
            end
        end 
    end
    // reg [ADDR_WIDTH-1:0] for_conv_row, for_conv_col;
    // for_conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_row <= 0;
        end else if (en) begin
            if ( for_conv_col + num_groups_reg >= ker_col ) begin
                if(for_conv_row < ker_row - 1)begin
                    for_conv_row <= for_conv_row + 1;
                end else begin
                    for_conv_row <= 0; // Reset when kernel window complete
                end
            end
        end 
        // else begin
        //     for_conv_row <= 0;
        // end
    end

    // for_conv_col Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_col <= 0;
        end else if (en) begin
            if (for_conv_col + num_groups_reg < ker_col) begin
                for_conv_col <= for_conv_col + num_groups_reg;
            end else begin
                for_conv_col <= 0;
            end
        end else begin
            for_conv_col <= 0;
        end
    end

    always @(posedge clk)begin
        for_conv_row_delay <= for_conv_row;
    end

    always @(posedge clk)begin
        for_conv_col_delay <= for_conv_col;
    end

    // control mac_valid_in
    always @(posedge clk) begin
        if (!rst) begin
            mac_valid_in <= 1'b0;
        end else if (en_delay && for_conv_row_delay == (ker_row-1)) begin
            mac_valid_in <= 1'b1;
        end else begin
            mac_valid_in <= 1'b0;
        end
    end

    //DEBUG:
    // reg [31:0] debug_cycle_count;
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         debug_cycle_count <= 0;
    //     end else begin
    //         debug_cycle_count <= debug_cycle_count + 1;
            
    //         // Debug prints
    //         if (en) begin
    //             $display("*[DEBUG]* Cycle: %d, for_conv_row=%d, for_conv_col=%d, conv_row=%d, conv_col=%d", 
    //                     debug_cycle_count, for_conv_row, for_conv_col, conv_row, conv_col);
    //         end
    //     end
    // end


    // control data_mac_o
    always @(posedge clk) begin
        if (!rst || !en) begin
            data_mac_o <= 0;
        end else if (en_delay) begin
            integer idx, group_idx;
            // idx = for_conv_row * ker_col + for_conv_col;
            // 如果ker_col > 8, 則需要做其他操作, tile整個convolution
            if(ker_col > 8)begin
                ;
            // 剩下的情況就是ker_col <= 8, 根據不同group的起始位置放入data
            end else begin
                // 1. idx 每次要取的數量要小於 nums_input
                // 2. idx 不能超過 ker_col
                // 3. (idx + for_conv_col_delay + for_conv_row_delay * ker_col) < total_macs 確保不超出範圍

                // macs_of_group = ker_row * ker_col
                // 每個 group 的 data 區間為 [group_idx * macs_of_group, group_idx * macs_of_group + macs_of_group-1]
                for(group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
                    // 確保這個 group 的起始位置不超過整個 data_mac_o 的最大範圍
                    if(group_idx * macs_of_group < MAX_MACS && group_idx < num_groups_reg) begin
                        for(idx = 0; idx < MAX_ITER ; idx = idx + 1) begin
                            if(idx < ker_col && idx < nums_input &&  (idx + for_conv_col_delay + for_conv_row_delay * ker_col) < total_macs) begin
                                data_mac_o[( (group_idx * macs_of_group) + idx + for_conv_row_delay * ker_col + for_conv_col) * DATA_WIDTH +: DATA_WIDTH ]
                                    <= data_in[( group_idx + idx ) * DATA_WIDTH +: DATA_WIDTH];
                            end
                        end
                    end
                end
            end
        end
    end


    always @(posedge clk) begin
        if (!rst) begin
            weight_idx <= 0;
        end else if (en) begin
            if (weight_idx + nums_input < total_macs) begin
                weight_idx <= weight_idx + nums_input;
            end else begin
                weight_idx <= weight_idx;
            end
        end else begin
            weight_idx <= 0;
        end
    end

    always @(posedge clk)begin
        weight_idx_delay <= weight_idx;
    end


    // control weight_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            weight_mac_o <= 0;
        end else if (en_delay) begin
            integer idx, group_idx;
            // 和 data_mac_i 類似的處理方式
            // 若 ker_col > 8 時需要其他處理（此處略），否則使用和 data_mac_i 相同的 group+idx 排列方式
            if (ker_col > 8) begin
                // 您可在這裡實作當 ker_col > 8 的相應處理邏輯
            end else begin
                // 將資料分配到各個 group 中
                // 每組 group 有 macs_of_group = ker_row * ker_col 個位置
                // 權重資料的線性位移以 weight_idx_delay + idx 計算
                // each group 的起始位置為 group_idx * macs_of_group

                for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
                    if (group_idx * macs_of_group < MAX_MACS && group_idx < num_groups_reg) begin
                        // idx 不可超過 nums_input、ker_col 且 (weight_idx_delay + idx) 不可超過 total_macs
                        for (idx = 0; idx < MAX_ITER; idx = idx + 1) begin
                            // 將權重資料放到對應的線性位置
                            // 線性位置： (group_idx * macs_of_group) + (weight_idx_delay + idx)
                            // 將 weight_in 中的第 (group_idx+idx) 筆資料對應到該位置
                            if((weight_idx_delay + idx) < total_macs)begin
                                weight_mac_o[((group_idx * macs_of_group) + (weight_idx_delay + idx)) * DATA_WIDTH +: DATA_WIDTH] 
                                    <= weight_in[idx * DATA_WIDTH +: DATA_WIDTH];
                            end
                        end
                    end
                end
            end
        end
    end

    // control output index
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         idx1_out <= 0;
    //     end else if (mac_valid_out) begin
    //         idx1_out <= idx1_out + 1;
    //     end
    // end


    



    // reg en_delay;
    
    // reg [ADDR_WIDTH-1:0] for_conv_row_delay;
    // reg [ADDR_WIDTH-1:0] for_conv_col_delay;

    // wire [6:0] shift_amount;
    // wire [6:0] nums_input;
    // assign shift_amount = $clog2(DATA_WIDTH); // 3
    // assign nums_input = SRAM_WIDTH_O >> shift_amount; // 64 / 2^3

    // reg [$clog2(MAX_MACS):0] data_count;
    // wire [$clog2(MAX_MACS):0] total_macs;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_i;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_i;

    // assign total_macs = ker_row * ker_col;
    // reg mac_valid_in;

    // wire [ADDR_WIDTH-1:0] out_row;
    // wire [ADDR_WIDTH-1:0] out_col;
    // assign out_row = img_row - ker_row + 1;
    // assign out_col = img_col - ker_col + 1;

    // // control output weight idx
    // reg [ADDR_WIDTH-1:0] weight_idx;
    // reg [ADDR_WIDTH-1:0] weight_idx_delay;
    // assign weight_idx_o = weight_idx;

    // always @(posedge clk) begin
    //     en_delay <= en;
    // end

    // // control convolution index
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         conv_col <= 0;
    //     end else if(conv_col == out_col - 1 && conv_row == out_row - 1  && mac_valid_in) begin
    //         conv_col <= 0;
    //     end else if (mac_valid_in) begin
    //         if (conv_col < out_col -1) begin
    //             conv_col <= conv_col + 1;  // Hold current value
    //         end else begin
    //             conv_col <= 0;
    //         end
    //     end 
    // end

    // // conv_row Logic
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         conv_row <= 0;
    //     end else if(conv_col == out_col - 1 && conv_row == out_row - 1 && mac_valid_in) begin
    //         conv_row <= 0; 
    //     end else if (mac_valid_in) begin
    //         if (conv_col < out_col - 1) begin
    //             conv_row <= conv_row;  // Hold current value
    //         end else begin
    //             conv_row <= conv_row + 1;
    //         end
    //     end 
    // end

    // // for_conv_row Logic
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         for_conv_row <= 0;
    //     end else if (en) begin
    //         if ( for_conv_col + nums_input >= ker_col ) begin
    //             for_conv_row <= for_conv_row + 1;
    //         end else begin
    //             for_conv_row <= for_conv_row;
    //         end
    //     end else begin
    //         for_conv_row <= 0;
    //     end
    // end

    // // for_conv_col Logic
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         for_conv_col <= 0;
    //     end else if (en) begin
    //         if (for_conv_col + nums_input < ker_col) begin
    //             for_conv_col <= for_conv_col + nums_input;
    //         end else begin
    //             for_conv_col <= 0;
    //         end
    //     end else begin
    //         for_conv_col <= 0;
    //     end
    // end

    // always @(posedge clk)begin
    //     for_conv_row_delay <= for_conv_row;
    // end

    // always @(posedge clk)begin
    //     for_conv_col_delay <= for_conv_col;
    // end

    // // control mac_valid_in
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         mac_valid_in <= 1'b0;
    //     end else if (en_delay && for_conv_row == ker_row  ) begin
    //         mac_valid_in <= 1'b1;
    //     end else begin
    //         mac_valid_in <= 1'b0;
    //     end
    // end



    // // control data_mac_i
    // always @(posedge clk) begin
    //     if (!rst || !en) begin
    //         data_mac_i <= 0;
    //     end else if (en_delay) begin
    //         integer idx;
    //         // idx = for_conv_row * ker_col + for_conv_col;
    //         // 1. idx每次要取的數量要小於nums_input, 2. 以及不能超過ker_col, 3. 還有要判斷是否超過total_macs
    //         for(idx = 0; idx < ker_col && idx < nums_input &&  (idx + for_conv_col_delay + for_conv_row_delay * ker_col) < total_macs; idx = idx + 1)begin
    //             data_mac_i[(idx + for_conv_row_delay * ker_col + for_conv_col) * DATA_WIDTH +: DATA_WIDTH] <= data_in[idx * DATA_WIDTH +: DATA_WIDTH];
    //         end
    //         // if (idx && idx <= total_macs) begin
    //         //     data_mac_i[(idx-1) * DATA_WIDTH +: DATA_WIDTH] <= data_in;
    //         // end
    //     end
    // end


    // always @(posedge clk) begin
    //     if (!rst) begin
    //         weight_idx <= 0;
    //     end else if (en) begin
    //         if (weight_idx < total_macs) begin
    //             weight_idx <= weight_idx + nums_input;
    //         end else begin
    //             weight_idx <= weight_idx;
    //         end
    //     end else begin
    //         weight_idx <= 0;
    //     end
    // end

    // always @(posedge clk)begin
    //     weight_idx_delay <= weight_idx;
    // end


    // // control weight_mac_i
    // always @(posedge clk) begin
    //     if (!rst || !en) begin
    //         weight_mac_i <= 0;
    //     end else if (en_delay) begin
    //         integer idx;
    //         // idx = for_conv_row * ker_col + for_conv_col;
    //         for(idx = 0;  idx < nums_input && idx + weight_idx_delay < total_macs ; idx = idx + 1)begin
    //             weight_mac_i[(weight_idx_delay + idx) * DATA_WIDTH +: DATA_WIDTH] <= weight_in[idx * DATA_WIDTH +: DATA_WIDTH];
    //         end
    //     end
    // end

    // // control data_count
    // always @(posedge clk) begin
    //     if (!rst || !en) begin
    //         data_count <= 0;
    //     end else if (en) begin
    //         integer idx;
    //         idx = for_conv_row * ker_col + for_conv_col;
    //         if (idx && idx <= total_macs) begin
    //             data_count <= data_count + 1;
    //         end
    //     end
    // end

    // // control output index
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         idx1_out <= 0;
    //     end else if (mac_valid_out) begin
    //         idx1_out <= idx1_out + 1;
    //     end
    // end


    // mac #
    // (
    //     .MAX_MACS(MAX_MACS),
    //     .DATA_WIDTH(DATA_WIDTH)
    // )
    // mac_gen (
    //     .clk(clk),
    //     .rst(rst),
    //     .num_macs_i(total_macs),
    //     .valid_in(mac_valid_in),
    //     .data(data_mac_i),
    //     .weight(weight_mac_i),
    //     .mac_out(mac_out),
    //     .valid_out(mac_valid_out)
    // );

endmodule