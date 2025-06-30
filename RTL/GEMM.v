`timescale 1ns / 1ps
`include "params.vh"

module GEMM #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8,
    parameter QUANT_WIDTH = 32,
    parameter MAC_BIT_PER_GROUP = 7,
    parameter MAX_GROUPS = 8
)
(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   init,
    //-----------------------------------------------------
    // convolution signals
    //-----------------------------------------------------
    // convolution signals
    // convolution en
    input  wire                   convolution_en,
    // input  wire                   fc_en,
    // convolution input metadata
    input  wire [ADDR_WIDTH-1:0]  img_row,
    input  wire [ADDR_WIDTH-1:0]  img_col,
    input  wire [ADDR_WIDTH-1:0]  ker_row,
    input  wire [ADDR_WIDTH-1:0]  ker_col,
    input  wire [ADDR_WIDTH-1:0]  in_channel,
    input  wire [ADDR_WIDTH-1:0]  out_channel,
    input  wire [3:0]             stride_h,
    input  wire [3:0]             stride_w,
    input  wire                   padding,
    // convolution img and kernel data
    input  wire [SRAM_WIDTH_O-1:0]  data_in,
    input  wire [SRAM_WIDTH_O-1:0]  weight_in,
    // convolution output signal control
    output wire                   mac_valid_out,
    output wire signed [MAX_GROUPS*DATA_WIDTH-1:0] GEMM_out,
    // convolution output image metadata
    output wire [ADDR_WIDTH-1:0]  conv_row,
    output wire [ADDR_WIDTH-1:0]  conv_col,
    output wire [MAX_ADDR_WIDTH-1:0]  input_data_idx,
    output wire [ADDR_WIDTH-1:0]  for_conv_row,
    output wire [ADDR_WIDTH-1:0]  for_conv_col,
    output wire [8:0]             input_data_cur_idx,
    // convolution output weight idx metadata
    output [MAX_ADDR_WIDTH-1:0]  weight_idx_o,
    output wire [31:0]  GEMM_results_counts,
    //-----------------------------------------------------
    // requant signals
    //-----------------------------------------------------
    input wire [31:0] quantized_multiplier,
    input signed [31:0] shift,
    input signed [31:0] output_offset,
    // output wire [MAX_VECTOR_SIZE * DATA_WIDTH - 1:0] conv_data_o,
    // output wire [MAX_VECTOR_SIZE * DATA_WIDTH - 1:0] fc_data_o,
    // output wire conv_valid_o,
    // output wire fc_valid_o,
    output wire [$clog2(MAX_GROUPS+1) -1:0] groups,
    output wire GEMM_valid_o
    // after requantout_size
    // output wire [ADDR_WIDTH-1:0]  requant_idx_o
);
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    // convolution signals
    wire mac_data_ready;
    wire [MAX_MACS*DATA_WIDTH-1:0] data_mac_i;
    wire [MAX_MACS*DATA_WIDTH-1:0] weight_mac_i;
    wire [$clog2(MAX_GROUPS+1) -1:0] num_groups_i;
    wire [MAX_GROUPS * MAC_BIT_PER_GROUP -1:0] num_macs_i;
    wire [MAX_GROUPS * QUANT_WIDTH-1:0] mac_to_conv_i;
    wire [$clog2(MAX_GROUPS+1) -1:0] num_groups_o;
    assign groups = num_groups_o;
    // requant pipeline signals
    reg [QUANT_WIDTH * MAX_GROUPS - 1 : 0] conv_to_requant_i;
    reg requant_input_valid;
    reg [QUANT_WIDTH-1 :0] conv_to_requant_32b_i;
    wire requant_output_valid_o[0:MAX_GROUPS-1];
    assign GEMM_valid_o = requant_output_valid_o[0];
    // groups_counter
    reg [$clog2(MAX_GROUPS+1) -1:0] groups_counter;
    // mac out to requant
    wire [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out_to_conv_i;
    // requant FIFO signals
    localparam FIFO_idle=0, FIFO_read=1, FIFO_requant=2;
    reg [2:0] FIFO_state, next_FIFO_state;
    wire fifo_full, fifo_empty;
    wire fifo_wr;
    reg  fifo_rd;
    wire [QUANT_WIDTH * MAX_GROUPS + $clog2(MAX_GROUPS+1) - 1 : 0] fifo_dout;
    // current group number and mac_out from FIFO
    reg [QUANT_WIDTH * MAX_GROUPS - 1 : 0] cur_macs_out;
    reg [$clog2(MAX_GROUPS+1) - 1 : 0] cur_num_groups;


    // signals for sum that macs > 64
    wire is_greater_64;
    wire [15:0] total_macs;
    wire [10:0] total_blocks;
    reg [10:0] cur_blocks;
    wire req_valid_in;
    assign total_macs = ker_row * ker_col * in_channel;
    assign total_blocks = (total_macs[5:0] != 0)? (total_macs[15:6] + 1) : total_macs[15:6];
    assign is_greater_64 = (total_macs > 64 )? 1 : 0;
    assign req_valid_in = (!is_greater_64)? mac_valid_out :
                          (is_greater_64 && mac_valid_out && (cur_blocks + 1 == total_blocks))? 1 : 0;
    reg signed [31:0] accu;
    wire signed [31:0] req_input;
    assign req_input = accu + mac_out_to_conv_i[31:0];

    always @(posedge clk) begin
        if(!rst) begin
            cur_blocks <= 0;
        end else if(init) begin
            cur_blocks <= 0;
        end else if(cur_blocks + 1 == total_blocks && mac_valid_out) begin
            cur_blocks <= 0;
        end else if(is_greater_64 && mac_valid_out) begin
            cur_blocks <= cur_blocks + 1;
        end
    end
    
    always @(posedge clk) begin
        if(!rst) begin
            accu <= 0;
        end else if(init) begin
            accu <= 0;
        end else if(req_valid_in) begin 
            accu <= 0;
        end else if(is_greater_64 && mac_valid_out) begin
            accu <= accu + $signed(mac_out_to_conv_i[31:0]);
        end
    end
    // FIFO FSM control
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         FIFO_state <= FIFO_idle;
    //     end else if(init) begin
    //         FIFO_state <= FIFO_idle;
    //     end else begin
    //         FIFO_state <= next_FIFO_state;
    //     end
    // end

    // always @(*) begin
    //     case(FIFO_state)
    //         FIFO_idle: begin
    //             next_FIFO_state = (!fifo_empty)? FIFO_read: FIFO_idle;
    //         end
    //         FIFO_read: begin
    //             next_FIFO_state = FIFO_requant;
    //         end
    //         FIFO_requant: begin
    //             if(groups_counter == (cur_num_groups-1) && !fifo_empty)begin
    //                 next_FIFO_state = FIFO_read;
    //             end else if(groups_counter == (cur_num_groups-1) && fifo_empty)begin
    //                 next_FIFO_state = FIFO_idle;
    //             end else if(groups_counter < (cur_num_groups-1))begin
    //                 next_FIFO_state = FIFO_requant;
    //             end
    //         end
    //         default: begin
    //             next_FIFO_state = FIFO_idle;
    //         end
    //     endcase
    // end

    // // FIFO write logic control
    // assign fifo_wr = (mac_valid_out && !fifo_full)? 1'b1: 1'b0;

    // // FIFO read logic control
    // // read from FIFO and store into fifo_data_reg
    // always @(posedge clk) begin
    //     if (!rst) begin
    //         fifo_rd <= 1'b0;
    //     end else if(init) begin
    //         fifo_rd <= 1'b0;
    //     end else if(FIFO_state == FIFO_read)begin
    //         fifo_rd <= 1'b1;
    //         // $display("****** groups_counter = %d, cur_num_groups = %d, fifo_empty = %d, fifo_rd = %d", groups_counter, cur_num_groups, fifo_empty, fifo_rd);
    //     end else begin
    //         fifo_rd <= 1'b0;
    //     end 
    // end

    // // read data => store in cur_num_groups & cur_macs_out
    // always @(*) begin
    //     if(!rst) begin
    //         { cur_num_groups, cur_macs_out } <= 0;
    //     end else if(init) begin
    //         { cur_num_groups, cur_macs_out } <= 0;
    //     end else if(fifo_rd) begin
    //         // 同周期 read => data_out 已經是本次讀出的資料 (zero-cycle read)
    //         { cur_num_groups, cur_macs_out } <= fifo_dout;
    //     end
    // end

    // // assign conv_to_requant_32b_i
    // always @(*)begin
    //     if(!rst)begin
    //         conv_to_requant_32b_i <= 0;
    //     end else if(init) begin
    //         conv_to_requant_32b_i <= 0; 
    //     end else if(requant_input_valid)begin
    //         conv_to_requant_32b_i <= cur_macs_out[QUANT_WIDTH * groups_counter  +: QUANT_WIDTH];
    //     end
    // end

    // // group counter: 計算到當前取到第幾個group, 表示我們要在fifo_data_reg取第幾個 32bits
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         groups_counter <= 0;
    //     // end else if(requant_input_valid) begin
    //     end else if(init) begin
    //         groups_counter <= 0; 
    //     end else if(requant_input_valid) begin
    //         groups_counter <= groups_counter + 1;
    //     end else begin
    //         groups_counter <= 0;
    //     end
    // end

    // // requant input valid signal control
    // // 1. groups_counter < num_groups_i - 1: 保持有效
    // // 2. groups_counter == 0 && rd == 1: 保持有效
    // always @(posedge clk) begin
    //     if(!rst) begin
    //         requant_input_valid <= 0;
    //     end else if(init) begin
    //         requant_input_valid <= 0; 
    //     end else if(FIFO_state == FIFO_requant && groups_counter < cur_num_groups-1) begin
    //         requant_input_valid <= 1;
    //     end else begin
    //         requant_input_valid <= 0;
    //     end
    // end

    // // MAC engine and MultiplyByQuantizedMultiplier pipeline FIFO buffer
    // FIFO #
    // (
    //     .DATA_WIDTH(QUANT_WIDTH * MAX_GROUPS + $clog2(MAX_GROUPS+1)),
    //     .DEPTH(131072),
    //     .ADDR_WIDTH(18)
    // ) mac_pipeline_fifo
    // (
    //     .clk(clk),
    //     .rst(rst),
    //     .wr(fifo_wr),
    //     .rd(fifo_rd),
    //     .data_in({ num_groups_o , mac_out_to_conv_i}),
    //     .data_out(fifo_dout),
    //     .full(fifo_full),
    //     .empty(fifo_empty)
    // );

    convolution #
    (
        .MAX_MACS(MAX_MACS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) convolution_inst
    (
        .clk(clk),
        .rst(rst),
        .init(init),
        .en(convolution_en),
        // input metadata
        .img_row(img_row),
        .img_col(img_col),
        .ker_row(ker_row),
        .ker_col(ker_col),
        .in_channel(in_channel),
        .output_channel(out_channel),
        .stride_col(stride_h),
        .stride_row(stride_w),
        .padding(padding),
        // img and kernel data
        .data_in(data_in),
        .weight_in(weight_in),
        // mac data renum_groups_oady
        .num_groups_o(num_groups_i),
        .num_macs_o(num_macs_i),
        .mac_data_ready_o(mac_data_ready),
        .data_mac_o(data_mac_i),
        .weight_mac_o(weight_mac_i),
        // output signal control
        // .mac_valid_out(mac_valid_out),
        // .mac_out(mac_out),
        .mac_out_to_sram(mac_out_to_conv_i),
        // output metadata
        .conv_row(conv_row),
        .conv_col(conv_col),
        .for_conv_row(for_conv_row),
        .for_conv_col(for_conv_col),
        .input_data_cur_idx(input_data_cur_idx),
        .input_data_idx(input_data_idx),
        .weight_idx_o(weight_idx_o)
        // .idx1_out(idx1_out)
    );


    mac #
    (
        .MAX_MACS(MAX_MACS)
    )
    mac_gen (
        .clk(clk),
        .rst(rst),
        .num_groups(num_groups_i),
        .num_macs_i(num_macs_i),
        .valid_in(mac_data_ready),
        .data(data_mac_i),
        .weight(weight_mac_i),
        .mac_out(mac_out_to_conv_i),
        .valid_out(mac_valid_out),
        .num_groups_o(num_groups_o)
    );

    wire signed [31:0] requant_data_o[0:MAX_GROUPS-1];
    // assign GEMM_out = ((requant_data_o + output_offset) >= $signed(POS_127))? $signed(POS_127):
    //                  ((requant_data_o + output_offset )<= $signed(NEG_128))? $signed(NEG_128): requant_data_o[7:0];

genvar requant_module_idx;
generate
    for(requant_module_idx = 0; requant_module_idx < MAX_GROUPS; requant_module_idx = requant_module_idx + 1) begin : requant
        wire [INT32_SIZE-1:0] requant_data_i;
        assign requant_data_i = (is_greater_64)? req_input: mac_out_to_conv_i[QUANT_WIDTH * requant_module_idx +: QUANT_WIDTH];
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
            .clk(clk),
            .rst(rst),
            .x(requant_data_i),
            .quantized_multiplier(quantized_multiplier),
            .shift(shift),
            // .input_valid(mac_valid_out),
            .input_valid(req_valid_in),
            .output_valid(requant_output_valid_o[requant_module_idx]),
            .x_mul_by_quantized_multiplier(requant_data_o[requant_module_idx])
        );
        assign GEMM_out[requant_module_idx * DATA_WIDTH +: DATA_WIDTH] = 
            ((requant_data_o[requant_module_idx] + output_offset) >= $signed(POS_127))? $signed(POS_127):
            ((requant_data_o[requant_module_idx] + output_offset )<= $signed(NEG_128))? $signed(NEG_128): requant_data_o[requant_module_idx][7:0];
    end
endgenerate
    // MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
    //     .clk(clk),
    //     .rst(rst),
    //     .x(conv_to_requant_32b_i),
    //     .quantized_multiplier(quantized_multiplier),
    //     .shift(shift),
    //     .input_valid(requant_input_valid),
    //     .output_valid(requant_output_valid_o),
    //     .x_mul_by_quantized_multiplier(requant_data_o)
    // ); 
    // requant_idx control by requant_output_valid_o 
    reg [31:0] requant_idx;
    always @(posedge clk)begin
        if(!rst)begin
            requant_idx <= 0;
        end else if(init) begin
            requant_idx <= 0; 
        end else if(GEMM_valid_o)begin
            requant_idx <= requant_idx + groups;
            // $display("requant_idx = %d, requant_value = %d", requant_idx,GEMM_out);
        end
    end

    assign GEMM_results_counts = requant_idx;

    
endmodule