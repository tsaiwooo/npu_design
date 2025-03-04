// 目前的問題是axi_stream_output的tvalid跟start_output不一樣導致addr錯誤, 取到錯的data, 還有存入sram的data有幾個也是錯的需要去debug
`timescale 1ns / 1ps
`include "params.vh"

module npu #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 8,
    parameter C_AXIS_MDATA_WIDTH = 8,
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1),
    parameter QUANT_WIDTH = 32
)
(
    /* AXI slave interface (input to the FIFO) */
    input  wire                   s00_axis_aclk,
    input  wire                   s00_axis_aresetn,
    input  wire signed [C_AXIS_TDATA_WIDTH-1:0]  s00_axis_tdata,
    input  wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0]   s00_axis_tstrb,
    input  wire                   s00_axis_tvalid,
    output wire                   s00_axis_tready,
    input  wire                   s00_axis_tlast,
    input  wire [4*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser,  

    /* AXI master interface (output of the FIFO) */
    input  wire                   m00_axis_aclk,
    input  wire                   m00_axis_aresetn,
    output wire signed [C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output wire [(C_AXIS_MDATA_WIDTH/8)-1 : 0]   m00_axis_tstrb, 
    output wire                   m00_axis_tvalid,
    input  wire                   m00_axis_tready,
    output wire                   m00_axis_tlast,
    output wire [NUM_CHANNELS_WIDTH-1:0]           m00_axis_tuser, 

    // requant signals
    input wire [31:0]            quantized_multiplier,
    input wire signed  [31:0]     shift,

    // dequant signals(zero_point, range_radius)
    input signed [31:0]     input_zero_point,
    input signed  [31:0]            input_range_radius,
    input signed  [31:0]            input_left_shift,
    input signed  [31:0]            input_multiplier,

    // output for cycles
    output reg [31:0] cycle_count
);

    reg [2:0] state = IDLE, next_state;
    reg start_output = 1'b0;
    reg GEMM_en = 1'b0;
    reg ELEMENT_en = 1'b0;

    // axi_stream_input signals
    wire                    write_enable;
    wire [MAX_ADDR_WIDTH-1:0]   write_address;
    wire signed [C_AXIS_TDATA_WIDTH-1:0] write_data;
    wire [2:0]              data_type;
    wire                    data_ready;
    wire [ADDR_WIDTH-1:0]   img_row;
    wire [ADDR_WIDTH-1:0]   img_col;
    wire [ADDR_WIDTH-1:0]   ker_row;
    wire [ADDR_WIDTH-1:0]   ker_col;
    wire [NUM_CHANNELS_WIDTH-1:0] num_channels;
    wire [3:0]             stride_h, stride_w;
    wire [ADDR_WIDTH-1:0]   in_channel, out_channel;
    wire                    padding ;
    wire [5:0]              input_data_idx;
    wire [ADDR_WIDTH-1:0]   batch;


    // axi_stream_output signals
    wire                   sram_out_en;
    wire [MAX_ADDR_WIDTH-1:0]  sram_out_addr;
    wire [MAX_ADDR_WIDTH-1:0]  out_size;

    // convolution signals
    wire signed [C_AXIS_MDATA_WIDTH - 1 : 0] mac_out;
    wire mac_valid_out;

    // output index control
    wire [MAX_ADDR_WIDTH-1:0] idx1_out;

    // output size
    wire [ADDR_WIDTH-1:0] out_row, out_col;
    wire [8:0]            patch;
    assign out_row = (img_row - ker_row + 1) / stride_w;
    assign out_col = (img_col - ker_col + 1) / stride_h;
    assign out_size = out_row * out_col * out_channel;
    assign patch = ker_row * in_channel;

    // GEMM convolution index
    wire [ADDR_WIDTH-1:0] conv_row;
    wire [ADDR_WIDTH-1:0] conv_col;
    wire [ADDR_WIDTH-1:0] for_conv_row;
    wire [ADDR_WIDTH-1:0] for_conv_col;
    wire [MAX_ADDR_WIDTH-1:0] weight_idx;
    wire [8:0]            input_data_cur_idx;


    // SRAM OUTPUT DATA
    wire signed [SRAM_WIDTH_O-1:0] gemm0_data_out;
    wire signed [SRAM_WIDTH_O-1:0] gemm1_data_out;
    wire signed [SRAM_WIDTH_O-1:0] elem_data_out;
    wire signed [SRAM_WIDTH_O-1:0] sram_data_out;

    // requant signals
    wire requant_valid_o;

    // sram_controller signals
    wire elem_en_sel;
    wire [MAX_ADDR_WIDTH-1:0] elem_addr_sel;

    // element_wise signals
    wire signed [C_AXIS_TDATA_WIDTH-1:0] element_wise_data_o;
    wire element_wise_valid_o;
    wire [17:0] element_wise_idx_o;
    reg element_wise_exp_en;
    reg element_wise_exp_en_delay;
    reg [17:0] element_wise_to_sram_exp_addr;

    // control FSM
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (data_ready && data_type == GEMM0_SRAM_IDX)
                    next_state = LOAD_IMG;
            end
            LOAD_IMG: begin
                if (data_ready && data_type == GEMM1_SRAM_IDX)
                    next_state = LOAD_KER;
            end
            LOAD_KER: begin
                // assum that the data is ready
                if (!data_ready)
                    next_state = COMPUTE_CONV0;
            end
            COMPUTE_CONV0: begin
                // if (conv_row >= out_row - 1 && conv_col >= out_col - 1 && for_conv_row == ker_row) begin
                //     next_state = WAIT_LAST;
                // end else if (for_conv_row == ker_row ) begin
                //     next_state = COMPUTE_CONV1;
                // end else begin
                //     next_state = COMPUTE_CONV0;
                // end
                next_state = (start_output)? WRITE_OUTPUT : COMPUTE_CONV0;
            end
            // COMPUTE_CONV1: begin
            //     next_state = COMPUTE_CONV0;
            // end
            // WAIT_LAST: begin
            //     if (mac_valid_out)
            //         next_state = WRITE_OUTPUT;
            // end
            WRITE_OUTPUT: begin
                if (sram_out_addr >= out_size)begin
                    next_state = IDLE;
                end 
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn)begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // control GEMM_en
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            GEMM_en <= 1'b0;
        end else if(conv_col >= (img_col - ker_col + 1) && conv_row >= (img_row - ker_row + 1))begin
            GEMM_en <= 1'b0;
        end else if(state == COMPUTE_CONV0)begin
            GEMM_en <= 1'b1;
        end else if(idx1_out >= (out_size -1))begin
            GEMM_en <= 1'b0;
        end
    end

    // control start_output
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            start_output <= 1'b0;
        end else if(element_wise_idx_o == (out_size-1) && state == COMPUTE_CONV0)begin
            start_output <= 1'b1;
        end
    end

    // control sram_en for element_wise
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            element_wise_exp_en <= 1'b0;
        end else if(idx1_out >= (out_size-1) && state == COMPUTE_CONV0 && element_wise_to_sram_exp_addr <= (out_size -1))begin
            element_wise_exp_en <= 1'b1;
            // $display("element_wise_exp_en = 1");
        end else if(element_wise_to_sram_exp_addr >= (out_size -1)) begin
            element_wise_exp_en <= 1'b0;
            // $display("element_wise_exp_en = 0");
        end 
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            element_wise_exp_en_delay <= 1'b0;
        end else begin
            element_wise_exp_en_delay <= element_wise_exp_en;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            element_wise_to_sram_exp_addr <= 0;
        end else if(element_wise_exp_en && element_wise_to_sram_exp_addr <= (out_size -1))begin
            element_wise_to_sram_exp_addr <= element_wise_to_sram_exp_addr + 1'b1;
            $display("element_wise_to_sram_exp_addr = %d", element_wise_to_sram_exp_addr);
        end
    end

    GEMM #
    (
        .MAX_MACS(MAX_MACS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(C_AXIS_TDATA_WIDTH)
    )
    GEMM_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        // convolution signals
        .convolution_en(GEMM_en),
        // input metadata
        .img_row(img_row),
        .img_col(img_col),
        .ker_row(ker_row),
        .ker_col(ker_col),
        .stride_h(stride_h),
        .stride_w(stride_w),
        .in_channel(in_channel),
        .out_channel(out_channel),
        .padding(padding),
        // img and kernel data
        .data_in(gemm0_data_out),
        .weight_in(gemm1_data_out),
        // output signal control
        .mac_valid_out(mac_valid_out),
        .mac_out(mac_out),
        // output metadata
        .conv_row(conv_row),
        .conv_col(conv_col),
        .input_data_idx(input_data_idx),
        .for_conv_row(for_conv_row),
        .for_conv_col(for_conv_col),
        .input_data_cur_idx(input_data_cur_idx),
        .weight_idx_o(weight_idx),
        // quantized multiplier and shift given by testbench temporarily
        .quantized_multiplier(quantized_multiplier),
        .shift(shift),
        .requant_valid_o(requant_valid_o),
        .idx1_out(idx1_out)
    );

    element_wise element_wise_gen
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .data_in(elem_data_out[7:0]),
        .valid_in(element_wise_exp_en_delay),
        .input_zero_point(input_zero_point),
        .input_range_radius(input_range_radius),
        .input_left_shift(input_left_shift),
        .input_multiplier(input_multiplier),
        .data_out(element_wise_data_o),
        .valid_out(element_wise_valid_o),
        .data_idx_o(element_wise_idx_o)
    ); 


    axi_stream_input #
    (
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(C_AXIS_TDATA_WIDTH),
        .NUM_CHANNELS_WIDTH(NUM_CHANNELS_WIDTH)
    )
    axi_stream_input_inst
    (
        .s_axis_aclk(s00_axis_aclk),
        .s_axis_aresetn(s00_axis_aresetn),
        .s_axis_tdata(s00_axis_tdata),
        .s_axis_tstrb(s00_axis_tstrb),
        .s_axis_tvalid(s00_axis_tvalid),
        .s_axis_tready(s00_axis_tready),
        .s_axis_tlast(s00_axis_tlast),
        .s_axis_tuser(s00_axis_tuser),
        .write_enable(write_enable),
        .write_address(write_address),
        .write_data(write_data),
        .data_type(data_type),
        .data_ready(data_ready),
        .img_row(img_row),
        .img_col(img_col),
        .ker_row(ker_row),
        .ker_col(ker_col),
        .batch(batch),
        .stride_h(stride_h),
        .stride_w(stride_w),
        .in_channel(in_channel),
        .output_channel(out_channel),
        .padding(padding),
        .num_channels(num_channels)
    );


    axi_stream_output #
    (
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(C_AXIS_MDATA_WIDTH),
        .NUM_CHANNELS_WIDTH(NUM_CHANNELS_WIDTH)
    )
    axi_stream_output_inst
    (
        .m_axis_aclk(m00_axis_aclk),
        .m_axis_aresetn(m00_axis_aresetn),
        .m_axis_tdata(m00_axis_tdata),
        // .m_axis_tstrb(m00_axis_tstrb),
        .m_axis_tvalid(m00_axis_tvalid),
        .m_axis_tready(m00_axis_tready),
        .m_axis_tlast(m00_axis_tlast),
        .m_axis_tuser(m00_axis_tuser),
        // SRAM interface
        .sram_out_en(sram_out_en),
        .sram_out_addr(sram_out_addr),
        .sram_out_data_out(sram_data_out),
        // control signals
        .start_output(state == WRITE_OUTPUT),
        .out_size(out_size)
    );
    wire [MAX_ADDR_WIDTH-1:0] gemm1_addr_i;
    // assign gemm1_addr_i = (conv_col * img_row + conv_row) * in_channel + input_data_idx;
    assign gemm1_addr_i = (ker_col == 1'b1 && ker_row == 1'b1)? (conv_col * img_row + conv_row) * in_channel + input_data_idx :
                        (((conv_col + for_conv_col) * img_row) + conv_row ) * in_channel + (input_data_cur_idx - for_conv_col * patch);
    assign elem_en_sel = requant_valid_o || element_wise_exp_en;
    assign elem_addr_sel = (requant_valid_o)? idx1_out:
                            (element_wise_exp_en)? element_wise_to_sram_exp_addr : 1'b0;
    sram_controller sram_controller_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        // GEMM1 port
        .gemm1_addr(gemm1_addr_i),
        .gemm1_data_in(),
        .gemm1_en(state == COMPUTE_CONV0),
        .gemm1_we(1'b0),
        .gemm1_idx(GEMM0_SRAM_IDX),
        .gemm1_data_out(gemm0_data_out),
        // GEMM2 port
        .gemm2_addr(weight_idx),
        .gemm2_data_in(),
        .gemm2_en(state == COMPUTE_CONV0),
        .gemm2_we(1'b0),
        .gemm2_idx(GEMM1_SRAM_IDX),
        .gemm2_data_out(gemm1_data_out),
        // ELEM0  port
        .elem_addr(elem_addr_sel),
        .elem_data_in(mac_out),
        // .elem_en(mac_valid_out),
        // .elem_we(mac_valid_out),
        .elem_en(elem_en_sel),
        .elem_we(requant_valid_o),
        .elem_idx(ELEM0_SRAM_IDX),
        .elem_data_out(elem_data_out),
        // ELEM1 port
        .elem1_addr(element_wise_idx_o),
        .elem1_data_in(element_wise_data_o),
        .elem1_en(element_wise_valid_o),
        .elem1_we(element_wise_valid_o),
        .elem1_idx(ELEM1_SRAM_IDX),
        .elem1_data_out(),
        // axi4 input port
        .write_address(write_address),
        .write_data(write_data),
        .axi_idx(data_type),
        .write_enable(write_enable),
        // axi4 output port
        .sram_out_en(sram_out_en),
        .sram_out_idx(ELEM1_SRAM_IDX),
        .sram_out_addr(sram_out_addr),
        .sram_out_data(sram_data_out)
    );

    // cycle count control
    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            cycle_count <= 0;
        end else if(state == COMPUTE_CONV0)begin
            cycle_count <= cycle_count + 1;
        end
    end 

endmodule
