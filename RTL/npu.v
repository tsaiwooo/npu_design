`timescale 1ns / 1ps
`include "params.vh"
// 目前傳送資料過去後卡住, dut運算有問題
module npu #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 8,
    parameter C_AXIS_MDATA_WIDTH = 8,
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1),
    parameter QUANT_WIDTH = 32,
    parameter MAX_VECTOR_SIZE = 8
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
    output wire signed [8*C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output wire [(8*C_AXIS_MDATA_WIDTH/8)-1 : 0]   m00_axis_tstrb, 
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

    // convolution signalsz
    wire signed [8*C_AXIS_MDATA_WIDTH - 1 : 0] mac_out;
    wire mac_valid_out;

    // output index control
    wire [MAX_ADDR_WIDTH-1:0] idx1_out;

    // output size
    wire [ADDR_WIDTH-1:0] out_row, out_col;
    assign out_row = (img_row - ker_row + 1) / stride_w;
    assign out_col = (img_col - ker_col + 1) / stride_h;
    assign out_size = out_row * out_col * out_channel;


    // GEMM convolution index
    wire [ADDR_WIDTH-1:0] conv_row;
    wire [ADDR_WIDTH-1:0] conv_col;
    // wire [ADDR_WIDTH-1:0] for_conv_row;
    // wire [ADDR_WIDTH-1:0] for_conv_col;
    wire [MAX_ADDR_WIDTH-1:0] weight_idx;

    // sram_controller signals
    wire [MAX_ADDR_WIDTH-1:0] gemm1_addr_i;
    assign gemm1_addr_i = (conv_col * img_row + conv_row) * in_channel + input_data_idx;

    // SRAM OUTPUT DATA
    wire signed [SRAM_WIDTH_O-1:0] gemm0_data_out;
    wire signed [SRAM_WIDTH_O-1:0] gemm1_data_out;
    wire signed [SRAM_WIDTH_O-1:0] elem_data_out;
    wire signed [SRAM_WIDTH_O-1:0] sram_data_out;

    // requant signals
    wire requant_valid_o;

    // GEMM output of stored_num_groups_o
    wire [2:0] stored_num_groups_o;

`ifndef synthesis
    wire [15:0] sram_result_addr;
`else
    wire [6:0] sram_result_addr;
`endif
    
    assign m00_axis_tstrb = stored_num_groups_o;

    // element-wise signals
    // -------------------------------------
    // exp
    // -------------------------------------
    wire [MAX_VECTOR_SIZE * C_AXIS_MDATA_WIDTH - 1:0] exp_data_o;
    wire exp_valid_o;

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
                next_state = (start_output)? WRITE_OUTPUT : COMPUTE_CONV0;
            end
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
        end else if(conv_row == out_row)begin
            GEMM_en <= 1'b0;
        end else if(state == COMPUTE_CONV0)begin
            GEMM_en <= 1'b1;
        end else if(stored_num_groups_o*idx1_out >= out_size -1)begin
            GEMM_en <= 1'b0;
        end
    end

    // control start_output
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            start_output <= 1'b0;
        end else if(stored_num_groups_o*idx1_out >= (out_size -1) && state == COMPUTE_CONV0)begin
            start_output <= 1'b1;
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
        // .for_conv_row(for_conv_row),
        // .for_conv_col(for_conv_col),
        .weight_idx_o(weight_idx),
        // quantized multiplier and shift given by testbench temporarily
        .quantized_multiplier(quantized_multiplier),
        .shift(shift),
        .requant_valid_o(requant_valid_o),
        .stored_num_groups_o(stored_num_groups_o)
        // .idx1_out(idx1_out)
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
        .out_size(out_size),
        .groups(stored_num_groups_o)
    );

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
        // ELEM port
        .elem_addr(idx1_out),
        .elem_data_in(),
        // .elem_en(mac_valid_out),
        // .elem_we(mac_valid_out),
        .elem_en(1'b0),
        .elem_we(1'b0),
        .elem_idx(ELEM0_SRAM_IDX),
        .elem_data_out(elem_data_out),
        // axi4 input port
        .write_address(write_address),
        .write_data(write_data),
        .axi_idx(data_type),
        .write_enable(write_enable),
        // axi4 output port
        .sram_out_en(1'b0),
        .sram_out_idx(ELEM0_SRAM_IDX),
        .sram_out_addr(sram_out_addr),
        .sram_out_data()
    );

    element_wise element_wise_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        // exp port
        .data_in(mac_out),
        .groups(stored_num_groups_o),
        .valid_in(requant_valid_o),
        .input_range_radius(input_range_radius),
        .input_zero_point(input_zero_point),
        .input_left_shift(input_left_shift),
        .input_multiplier(input_multiplier),
        .data_out(exp_data_o),
        .valid_out(exp_valid_o),
        .idx1_out(idx1_out)
    );
    
    // sram_result addr_i 協定, 可能是用來儲存or讀取
    assign sram_result_addr = (sram_out_en)? sram_out_addr : 
                              (exp_valid_o)? idx1_out : 0;
    sram_64bits #
    (
        .DATA_WIDTH(sram_64bits_width),
        .N_ENTRIES(sram_64bits_depth)
    ) sram_result
    (
        .clk_i(s00_axis_aclk),
        .en_i(sram_out_en || exp_valid_o),
        .we_i(exp_valid_o),
        .addr_i(sram_result_addr),
        .data_i(exp_data_o),
        .data_o(sram_data_out)
    );
   

    // cycle count control
    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            cycle_count <= 0;
        end else if(state == COMPUTE_CONV0)begin
            cycle_count <= cycle_count + 1;
        end
    end 

    // DEBUG INFO
    always @(posedge s00_axis_aclk)begin
        if(exp_valid_o)begin
            $display("exp_data_o: %d, idx1_out: %d, out_size = %d, out_row = %d, out_col = %d, out_channel = %d, img_row = %d, img_col = %d, stride_h = %d, stride_w = %d, stored_num_groups_o = %d", exp_data_o,idx1_out,out_size,out_row,out_col,out_channel,img_row,img_col,stride_h,stride_w,stored_num_groups_o);
        end
    end
endmodule
