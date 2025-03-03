`timescale 1ns / 1ps
`include "params.vh"

module GEMM #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8,
    parameter MAX_ADDR_WIDTH = 18,
    parameter QUANT_WIDTH = 32,
    parameter MAC_BIT_PER_GROUP = 6,
    parameter MAX_GROUPS = 8,
    parameter MAX_VECTOR_SIZE = 8
)
(
    input  wire                   clk,
    input  wire                   rst,
    //-----------------------------------------------------
    // convolution signals
    //-----------------------------------------------------
    // convolution signals
    // convolution en
    input  wire                   convolution_en,
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
    output wire signed [8*DATA_WIDTH-1:0] mac_out,
    // convolution output image metadata
    output wire [ADDR_WIDTH-1:0]  conv_row,
    output wire [ADDR_WIDTH-1:0]  conv_col,
    output wire [5:0]  input_data_idx,
    output wire [ADDR_WIDTH-1:0]  for_conv_row,
    output wire [ADDR_WIDTH-1:0]  for_conv_col,
    output wire [8:0]             input_data_cur_idx,
    // convolution output weight idx metadata
    output [MAX_ADDR_WIDTH-1:0]  weight_idx_o,
    // output wire [17:0]  idx1_out,
    //-----------------------------------------------------
    // requant signals
    //-----------------------------------------------------
    input wire [31:0] quantized_multiplier,
    input signed [31:0] shift,
    output wire requant_valid_o,
    // after requant
    // output wire [ADDR_WIDTH-1:0]  requant_idx_o
    // requant num of groups
    output reg [2:0] stored_num_groups_o
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
    
    // requant pipeline signals
    reg [QUANT_WIDTH * MAX_GROUPS - 1 : 0] conv_to_requant_i;
    reg requant_input_valid;
    reg [QUANT_WIDTH-1 :0] conv_to_requant_32b_i;
    wire signed [QUANT_WIDTH-1 :0] requant_32bits_out;
    wire signed [DATA_WIDTH-1 :0] requant_8bits_out;
    wire requant_output_valid_o;
    assign requant_valid_o = requant_output_valid_o;
    // assign mac_out = requant_8bits_out;
    assign requant_8bits_out = (requant_32bits_out > $signed(POS_127))? POS_127:
                                (requant_32bits_out < $signed(NEG_128))? NEG_128: requant_32bits_out;
    // groups_counter
    reg [$clog2(MAX_GROUPS+1) -1:0] groups_counter;
    // mac out to requant
    wire [MAX_GROUPS * QUANT_WIDTH-1:0] mac_out_to_conv_i;
    // requant FIFO signals
    localparam [2:0] FIFO_idle=0, FIFO_read=1, FIFO_requant=2;
    reg [2:0] FIFO_state, next_FIFO_state;
    wire fifo_full, fifo_empty;
    reg  fifo_wr, fifo_rd;
    wire [QUANT_WIDTH * MAX_GROUPS + $clog2(MAX_GROUPS+1) - 1 : 0] fifo_dout;
    // current group number and mac_out from FIFO
    reg [QUANT_WIDTH * MAX_GROUPS - 1 : 0] cur_macs_out;
    reg [$clog2(MAX_GROUPS+1) - 1 : 0] cur_num_groups;

    //store num_groups_o and flag
    reg is_stored = 0;
    // reg [2:0] stored_num_groups_o;

    always @(posedge clk)begin
        if(!rst)begin
            is_stored <= 0;
        end else if(mac_valid_out && !is_stored)begin
            is_stored <= 1;
        end
    end

    always @(posedge clk)begin
        if(!rst)begin
            stored_num_groups_o <= 0;
        end else if(is_stored)begin
            stored_num_groups_o <= num_groups_o;
        end
    end

    convolution #
    (
        .MAX_MACS(MAX_MACS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) convolution_inst
    (
        .clk(clk),
        .rst(rst),
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
        // mac data ready
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
        .MAX_MACS(MAX_MACS),
        .DATA_WIDTH(DATA_WIDTH)
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
    // vector signals for requant 
    wire [MAX_VECTOR_SIZE-1:0] requant_input_valid_array;
    wire [MAX_VECTOR_SIZE-1:0] requant_output_valid_o_array;
    wire signed [QUANT_WIDTH-1:0] requant_32bits_out_array[0:MAX_VECTOR_SIZE-1];
    wire signed [DATA_WIDTH-1:0] requant_8bits_out_array[0:MAX_VECTOR_SIZE-1];

    // always @(posedge clk) begin
    //     if(mac_valid_out)begin
    //         $display("mac_valid_out, groups = %d", num_groups_o);
    //     end
    // end
genvar requant_muodule_idx; 
generate
    for(requant_muodule_idx = 0; requant_muodule_idx < MAX_VECTOR_SIZE; requant_muodule_idx = requant_muodule_idx + 1)begin: requant_vector   
        MultiplyByQuantizedMultiplier MultiplyByQuantizedMultiplier_inst(
            .clk(clk),
            .rst(rst),
            .x(mac_out_to_conv_i[requant_muodule_idx * QUANT_WIDTH +: QUANT_WIDTH]),
            .quantized_multiplier(quantized_multiplier),
            .shift(shift),
            .input_valid(requant_input_valid_array[requant_muodule_idx]),
            .output_valid(requant_output_valid_o_array[requant_muodule_idx]),
            .x_mul_by_quantized_multiplier(requant_32bits_out_array[requant_muodule_idx])
        ); 

        // requant input valid signal control
        assign requant_input_valid_array[requant_muodule_idx] = (requant_muodule_idx < num_groups_o && mac_valid_out)? 1 : 0;
        // requant output data saturate
        assign requant_8bits_out_array[requant_muodule_idx] = (requant_32bits_out_array[requant_muodule_idx] >= $signed(POS_127))? $signed(POS_127):
                                (requant_32bits_out_array[requant_muodule_idx] <= $signed(NEG_128))? $signed(NEG_128): requant_32bits_out_array[requant_muodule_idx][7:0];
    end
endgenerate
    assign requant_output_valid_o = requant_output_valid_o_array[0];
    assign mac_out = { requant_8bits_out_array[7], requant_8bits_out_array[6], requant_8bits_out_array[5], requant_8bits_out_array[4], requant_8bits_out_array[3], requant_8bits_out_array[2], requant_8bits_out_array[1], requant_8bits_out_array[0]};

    // requant_idx control by requant_output_valid_o 
    reg [17:0] requant_idx;
    always @(posedge clk)begin
        if(!rst)begin
            requant_idx <= 0;
        end else if(requant_output_valid_o)begin
            requant_idx <= requant_idx + 1;
        end
    end

    // assign idx1_out = requant_idx;

    // DEBUG INFO
    always @(posedge clk)begin
        if(mac_valid_out)begin
            $display("mac_valid_out: %h, groups = %d",mac_out_to_conv_i, num_groups_o);
        end
        if(mac_data_ready) begin
            $display("data_mac_i: %h, weight_mac_i: %h", data_in, weight_in);
        end
    end
    
endmodule