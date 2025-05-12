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
    input  wire                   init,
    input  wire                   en,
    // input metadata
    input  wire [ADDR_WIDTH-1:0]  img_row,
    input  wire [ADDR_WIDTH-1:0]  img_col,
    input  wire [ADDR_WIDTH-1:0]  ker_row,
    input  wire [ADDR_WIDTH-1:0]  ker_col,
    input  wire [ADDR_WIDTH-1:0]  in_channel,
    input  wire [ADDR_WIDTH-1:0]  output_channel,
    // img and kernel data from sram
    input  wire [SRAM_WIDTH_O-1:0]  data_in,
    input  wire [SRAM_WIDTH_O-1:0]  weight_in,
    // stride, padding, dilation
    input  wire [3:0]  stride_row,
    input  wire [3:0]  stride_col,
    input  wire                   padding,
    // output signal control that mac data is ready
    output wire                   mac_data_ready_o,
    output reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_o,
    output reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_o,
    // output number of groups
    output wire [3:0]             num_groups_o,
    // output number macs of each group
    output wire [MAX_GROUPS * MAC_BIT_PER_GROUP - 1:0] num_macs_o,
    // input mac_out data from mac
    // input wire signed [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out,
    // output mac_out data from mac to sram_controller to store result because of multiple outputs
    output signed [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out_to_sram,
    // output image metadata
    output reg [ADDR_WIDTH-1:0]  conv_row,
    output reg [ADDR_WIDTH-1:0]  conv_col,
    output  [ADDR_WIDTH-1:0]  for_conv_row,
    output  [ADDR_WIDTH-1:0]  for_conv_col,
    output  reg [8:0]  input_data_cur_idx,
    // output weight idx metadata
    output [5:0]                 input_data_idx,
    output [MAX_ADDR_WIDTH-1:0]  weight_idx_o
    // output reg [ADDR_WIDTH-1:0]  idx1_out
);
    // FSM
    localparam [2:0] S_IDLE = 3'b000, S_1 = 3'b001, S_2 = 3'b010, S_3 = 3'b011, S_4 = 3'b100, S_5 = 3'b101;
    reg [2:0] state, next_state;

    // mac number of each group
    wire [6:0] macs_of_group;
    assign macs_of_group = ker_col * ker_row * in_channel;

    reg en_delay;
    // for loop row & col control
    reg [ADDR_WIDTH-1:0] for_conv_row_reg;
    reg [ADDR_WIDTH-1:0] for_conv_col_reg;
    reg [ADDR_WIDTH-1:0] for_conv_col_reg_delay;
    assign for_conv_row = for_conv_row_reg;
    assign for_conv_col = for_conv_col_reg;
    wire [8:0] patch;
    reg [8:0] input_data_cur_idx_delay;
    assign patch = ker_row * in_channel;

    wire [6:0] shift_amount;
    wire [6:0] nums_input;
    assign shift_amount = $clog2(DATA_WIDTH); // 3
    assign nums_input = SRAM_WIDTH_O >> shift_amount; // 64 / 2^3, 最多一次能從sram取得的data數量

    wire [$clog2(MAX_MACS):0] total_macs;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_o;
    // reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_o;

    assign total_macs = ker_row * ker_col * in_channel;
    // mac data ready
    reg mac_valid_in;
    assign mac_data_ready_o = mac_valid_in;

    wire [ADDR_WIDTH-1:0] out_row;
    wire [ADDR_WIDTH-1:0] out_col;
    //-------------------------------------------------------------------------
    // 輸出尺寸計算：根據 stride、padding 與 dilation (分 row 與 col)
    // 若 padding==1 (SAME): out_dim = ceil(img_dim/stride), 需要補0
    // 若 padding==0 (VALID): out_dim = floor((img_dim - dilation*(ker_dim-1) - 1)/stride + 1)
    assign out_row = padding ? ((img_row + stride_row - 1) / stride_row)
                           : (((img_row - ker_row) / stride_row) + 1);
    assign out_col = padding ? ((img_col + stride_col - 1) / stride_col)
                           : (((img_col - ker_col) / stride_col) + 1);
    // assign out_row = padding? img_row - ker_row + 1;
    // assign out_col = img_col - ker_col + 1;

    // control output weight idx
    reg [MAX_ADDR_WIDTH-1:0] weight_idx;
    reg [MAX_ADDR_WIDTH-1:0] weight_idx_delay;
    assign weight_idx_o = weight_idx;
    // 計算每次有多少個group
    reg [3:0] num_groups_reg; 
    reg [3:0] groups;
    reg [7:0] remaining;
    reg [MAX_GROUPS * MAC_BIT_PER_GROUP - 1:0] num_macs_reg_all;
    assign num_groups_o = num_groups_reg;
    assign num_macs_o = num_macs_reg_all;

    // for loop row & col control
    // reg [7:0] for_conv_row, for_conv_col;

    // 一次可以取8個data, 其中最多可以有8 - ker_col + 1個group
    wire [2:0] groups_of_eight;
    assign groups_of_eight = MAX_GROUPS - ker_col + 1;

    // input_idx & weight_idx
    reg [5:0] input_idx;
    reg [5:0] input_idx_delay;
    assign input_data_idx = input_idx;
    // output_channel_idx
    reg [8:0] output_channel_idx;
    
    reg [15:0] weight_start_idx;
    // input & weight buffer
    reg [INT8_SIZE * 512 -1: 0] weight_buffer;
    // reg [INT8_SIZE * MAX_MACS -1: 0] input_buffer;
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                next_state = (en)? S_1 : S_IDLE;
            end
            S_1: begin
                if(ker_row == 1'b1) begin
                    next_state = (input_idx_delay >= total_macs )? S_2 :
                             (conv_col == (img_col-1) && conv_row == (img_row-1))? S_IDLE: S_1;
                end else begin
                    next_state = (input_data_cur_idx == patch * ker_col)? S_2 :  
                             (conv_col+stride_col == (img_col-ker_col+1) && conv_row+stride_row == (img_row-ker_row+1))? S_IDLE: S_1;
                end
                // next_state = (input_idx_delay >= total_macs && ker_row == 1'b1 )? S_2 :
                //              (conv_col == (img_col-1) && conv_row == (img_row-1) && ker_row == 1'b1)? S_IDLE:
                //              (input_data_cur_idx == patch * ker_col)? S_2 :  
                //              (conv_col+stride_col == (img_col-ker_col+1) && conv_row+stride_row == (img_row-ker_row+1))? S_IDLE: S_1;
            end
            S_2: begin
                next_state = (weight_idx_delay >= (output_channel) * total_macs)? S_3: S_2;
                // next_state = (output_channel_idx == output_channel * total_macs)? S_3: S_2;
            end
            S_3: begin
                if(ker_row == 1'b1) begin
                    next_state = S_4;
                end else begin
                    next_state = (conv_col + stride_col >= img_col-1)? S_IDLE: S_4;
                end
            end
            S_4: begin
                if(ker_row == 1'b1)begin
                    next_state = ((input_idx_delay+nums_input) >= total_macs )? S_5: S_4;
                end else begin
                    next_state = (input_data_cur_idx == patch * ker_col)? S_5 : S_4;
                end
                // next_state = ((input_idx_delay+nums_input) >= total_macs && ker_row == 1'b1)? S_5 :
                //              (input_data_cur_idx == patch * ker_col && ker_row != 1'b1)? S_5 : S_4;
            end
            S_5: begin
                // next_state = (weight_idx_delay == output_channel * total_macs)? S_3 : 
                if(ker_row == 1'b1)begin
                    next_state = ( ker_row == 1'b1 && (conv_row + stride_row) >= (out_row) && (conv_col + stride_col) >= (out_col) && (output_channel_idx + num_groups_o) >= (output_channel-1))? S_IDLE :
                                ((output_channel_idx + num_groups_reg) >= (output_channel-1))? S_3 : S_5;
                end else begin
                    next_state = ( (conv_row + stride_row + ker_row ) >= (img_row+1) && (conv_col + stride_col + ker_col ) >= (img_col +1 ) && (output_channel_idx + num_groups_o) >= (output_channel-1))? S_IDLE :
                                 ((output_channel_idx + num_groups_reg) >= (output_channel-1))? S_3 : S_5;
                end
                // next_state =  ((conv_row + stride_row) >= (out_row) && (conv_col + stride_col) >= (out_col) && (output_channel_idx + num_groups_o) >= (output_channel-1))? S_IDLE :
                //              ( (conv_row + stride_row + ker_row ) >= (img_row+1) && (conv_col + stride_col + ker_col ) >= (img_col +1 ) && (output_channel_idx + num_groups_o) >= (output_channel-1))? S_IDLE :
                //              ((output_channel_idx + num_groups_reg) >= (output_channel-1))? S_3 : S_5;
            end
            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk)begin
        if(!rst) begin
            state <= S_IDLE;
        end else if(init) begin
            state <= S_IDLE; 
        end else begin
            state <= next_state;
        end
    end

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

        // if(conv_col + groups >= out_col)begin
        //     num_groups_reg = (groups_of_eight < groups)? groups_of_eight : out_col - conv_col;
        // end else begin
        //     num_groups_reg = (groups_of_eight < groups)? groups_of_eight : groups;
        // end
        num_groups_reg = groups;
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


    // weight_buffer store Logic
    always @(posedge clk)begin
        if(!rst) begin
            weight_buffer <= 0;
        end else if(init) begin
            weight_buffer <= 0; 
        end else if((state == S_1 || state == S_2)) begin
            weight_buffer[weight_idx_delay * INT8_SIZE +: INT64_SIZE] <= weight_in;
            $display("*[DEBUG]* weight_idx_delay = %d, weight_in = %h", weight_idx_delay, weight_in);
        end
    end

    // for_conv_col Logic
    always @(posedge clk)begin
        if(!rst)begin
            for_conv_col_reg <= 0;
        end else if(init) begin
            for_conv_col_reg <= 0; 
        end else if(state == S_1 || state == S_4) begin
            if(input_data_cur_idx + nums_input < (for_conv_col_reg + 1) * patch) begin
                for_conv_col_reg <= for_conv_col_reg;
            end else if(input_data_cur_idx + nums_input >= (for_conv_col_reg + 1) * patch) begin
                for_conv_col_reg <= for_conv_col_reg + 1'b1;
            end
        end else begin
            for_conv_col_reg <= 0;
        end
    end

    always @(posedge clk)begin
        if(!rst) begin
            for_conv_col_reg_delay <= 0;
        end else if(init) begin
            for_conv_col_reg_delay <= 0;
        end else begin
            for_conv_col_reg_delay <= for_conv_col_reg;
        end
    end

    // input_data_cur_idx Logic
    always @(posedge clk)begin
        if(!rst)begin
            input_data_cur_idx <= 0;
        end else if(init) begin
            input_data_cur_idx <= 0; 
        end else if(state == S_1 || state == S_4) begin
            if(input_data_cur_idx + nums_input < (for_conv_col_reg + 1) * patch) begin
                input_data_cur_idx <= input_data_cur_idx + nums_input;
            end else if(input_data_cur_idx + nums_input >= (for_conv_col_reg + 1) * patch) begin
                input_data_cur_idx <= (for_conv_col_reg + 1) * patch;
            end
        end else begin
            input_data_cur_idx <= 0;
        end
    end

    always @(posedge clk)begin
        if(!rst) begin
            input_data_cur_idx_delay <= 0;
        end else if(init) begin
            input_data_cur_idx_delay <= 0;
        end else begin
            input_data_cur_idx_delay <= input_data_cur_idx;
        end
    end

    // control convolution index
    always @(posedge clk) begin
        if (!rst) begin
            conv_col <= 0;
        end else if(init) begin
            conv_col <= 0; 
        end else if (ker_row == 1'b1 && state == S_3 && conv_row + stride_row >= out_row ) begin
            conv_col <= conv_col + stride_col;
        end else if (state == S_3 && conv_row + stride_row  + ker_row>= img_row+1 ) begin
            conv_col <= conv_col + stride_col;
        end 
    end

    // conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            conv_row <= 0;
        end else if(init) begin
            conv_row <= 0; 
        end else if(ker_row == 1'b1 && state == S_3 && conv_row + stride_row >= out_row) begin
            conv_row <= 0;
        end else if(state == S_3 && conv_row + stride_row + ker_row>= img_row+1) begin
            conv_row <= 0;
        end else if (state == S_3  ) begin
            conv_row <= conv_row + stride_row;
        end 
    end

    // input_idx Logic
    always @(posedge clk) begin
        if(!rst) begin
            input_idx <= 0;
        end else if(init) begin
            input_idx <= 0;
        end else if (en) begin
            if((state == S_1 || state == S_4)) begin
                input_idx <= input_idx + nums_input;
            end else begin
                input_idx <= 0;
            end
        end
    end

    // input_idx_delay
    always @(posedge clk)begin
        input_idx_delay <= input_idx;
    end


    // output_channel_idx Logic
    always @(posedge clk) begin
        if(!rst) begin
            output_channel_idx <= 0;
        end else if(init) begin
            output_channel_idx <= 0; 
        end else if ((state == S_2 || state == S_1) && weight_idx_delay + nums_input >= output_channel_idx * total_macs) begin
            output_channel_idx <= output_channel_idx + 1'd1;
        end else if(state == S_5) begin
            output_channel_idx <= output_channel_idx + num_groups_reg;
        end else if(state == S_3) begin
            output_channel_idx <= 0;
        end
    end


    // control mac_valid_in
    always @(posedge clk) begin
        if (!rst) begin
            mac_valid_in <= 1'b0;
        end else if(init) begin
            mac_valid_in <= 1'b0; 
        end else if(state == S_5) begin // 等到input好且weight也好
            mac_valid_in <= 1'b1;
        end else if (state == S_2  && (weight_idx_delay + nums_input) >= (output_channel_idx) * total_macs && !output_channel_idx[0]) begin // input好但是weight還再第一次load
            mac_valid_in <= 1'b1;
        end else begin
            mac_valid_in <= 1'b0;
        end
    end

    


    // control data_mac_o
    wire [6:0] valid_count;
    assign valid_count = ((input_data_cur_idx_delay + nums_input) <= total_macs)? nums_input: total_macs - input_data_cur_idx_delay;
    integer input_mac_for_i,k;
    always @(posedge clk) begin
        if (!rst || !en) begin
            data_mac_o <= 0;
        end else if(init) begin
            data_mac_o <= 0; 
        end else if (en_delay) begin
            if(state == S_1 || state == S_4)begin
                // directly put data to data_mac_o due to data is continuous in sram
                for(input_mac_for_i=0; input_mac_for_i < 8; input_mac_for_i = input_mac_for_i + 1)begin
                    if(input_mac_for_i < num_groups_reg) begin
                        if(ker_col == 1'b1 && ker_row == 1'b1 && input_idx_delay < total_macs) begin
                            data_mac_o[input_mac_for_i*total_macs*INT8_SIZE + input_idx_delay * DATA_WIDTH +: INT64_SIZE] <= data_in;
                        end else begin
                            for(k=0; k < 8; k = k + 1)begin
                                if(k<valid_count)
                                    data_mac_o[input_mac_for_i*total_macs*INT8_SIZE + (input_data_cur_idx_delay + k) * DATA_WIDTH +: DATA_WIDTH] <= data_in[k*DATA_WIDTH +: DATA_WIDTH];
                            end
                            // data_mac_o[input_mac_for_i*total_macs*INT8_SIZE + input_data_cur_idx_delay * DATA_WIDTH +: INT64_SIZE] <= data_in;
                        end
                    end
                end
            end
        end
    end


    always @(posedge clk) begin
        if (!rst) begin
            weight_idx <= 0;
        end else if(init) begin
            weight_idx <= 0; 
        end else if (en) begin
            if(state == S_1 || state == S_2) begin
                if(ker_row == 1'b1) begin
                    weight_idx <= weight_idx + nums_input;
                end else begin
                    if(weight_idx + nums_input >= output_channel_idx * total_macs &&  !output_channel_idx[0] )begin
                        weight_idx <= output_channel_idx * total_macs;
                    end else begin
                        weight_idx <= weight_idx + nums_input;
                    end
                end
            end else begin
                weight_idx <= 0;
            end
        end
    end

    always @(posedge clk)begin
        weight_idx_delay <= weight_idx;
    end

    // weight_start_idx Logic
    always @(posedge clk) begin
        if (!rst) begin
            weight_start_idx <= 0;
        end else if(init) begin
            weight_start_idx <= 0;  
        end else if ((S_1 || S_2) && en_delay) begin
            if(ker_row == 1'b1) begin
                if (weight_start_idx + nums_input < num_groups_reg * total_macs && weight_idx) begin
                    weight_start_idx <= weight_start_idx + nums_input;
                end else if(weight_start_idx + nums_input >= num_groups_reg * total_macs)begin
                    weight_start_idx <= 0;
                end
            end else begin
                if (weight_start_idx  < num_groups_reg * total_macs && weight_idx) begin
                    weight_start_idx <= weight_start_idx + nums_input;
                end else if(weight_start_idx  >= num_groups_reg * total_macs)begin
                    weight_start_idx <= 0;
                end
            end
        end
    end


    // control weight_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            weight_mac_o <= 0;
        end else if(init) begin
            weight_mac_o <= 0; 
        end else if (en_delay) begin
            if(state == S_5)begin
                weight_mac_o <= weight_buffer[output_channel_idx * total_macs * INT8_SIZE +: 512];
            // end else if((state == S_1 || state == S_2) && (weight_idx_delay + nums_input) >= (output_channel_idx) * total_macs && !output_channel_idx[0]) begin
            end else if((state == S_1 || state == S_2)) begin
                // weight_mac_o[(weight_idx_delay - (output_channel_idx-1) * total_macs) * DATA_WIDTH +: INT64_SIZE] <= weight_in;
                weight_mac_o[weight_start_idx * DATA_WIDTH +: INT64_SIZE] <= weight_in;
            end
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
    //             $display("*[DEBUG]* Cycle: %d, output_channel_idx=%d, output_channel=%d, conv_row=%d, conv_col=%d", 
    //                     debug_cycle_count, output_channel_idx, output_channel, conv_row, conv_col);
    //         end
    //     end
    // end
 
endmodule