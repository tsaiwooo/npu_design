`timescale 1ns / 1ps
`include "params.vh"

module npu #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 8,
    parameter C_AXIS_MDATA_WIDTH = 8,
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1)
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
    input  wire [2*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser,  // 用于通道数量

    /* AXI master interface (output of the FIFO) */
    input  wire                   m00_axis_aclk,
    input  wire                   m00_axis_aresetn,
    output wire signed [2*C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output wire [(2*C_AXIS_MDATA_WIDTH/8)-1 : 0]   m00_axis_tstrb, // 如果需要，可取消注释
    output wire                   m00_axis_tvalid,
    input  wire                   m00_axis_tready,
    output wire                   m00_axis_tlast,
    output wire [NUM_CHANNELS_WIDTH-1:0]           m00_axis_tuser  // 用于通道数量
);

    reg [2:0] state = IDLE, next_state;

    // 从 axi_stream_input 模块获取的信号
    wire                    write_enable;
    wire [ADDR_WIDTH-1:0]   write_address;
    wire signed [C_AXIS_TDATA_WIDTH-1:0] write_data;
    wire [2:0]              data_type;
    wire                    data_ready;
    wire [ADDR_WIDTH-1:0]   img_row;
    wire [ADDR_WIDTH-1:0]   img_col;
    wire [ADDR_WIDTH-1:0]   ker_row;
    wire [ADDR_WIDTH-1:0]   ker_col;
    wire [NUM_CHANNELS_WIDTH-1:0] num_channels;


    // axi_stream_output signals
    wire                   sram_out_en;
    wire [ADDR_WIDTH-1:0]  sram_out_addr;

    // // 图像和卷积核尺寸寄存器
    reg  [ADDR_WIDTH-1:0] img_row_reg, img_col_reg, ker_row_reg, ker_col_reg;

    // MAC 单元信号
    wire [$clog2(MAX_MACS+1)-1:0] num_macs_i;
    reg  [C_AXIS_TDATA_WIDTH * MAX_MACS - 1 : 0] data_mac_i;
    reg  [C_AXIS_TDATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_i;
    wire signed [2*C_AXIS_MDATA_WIDTH - 1 : 0] mac_out;
    wire mac_valid_out;
    reg mac_valid_in;

    // 数据加载计数器
    reg [$clog2(MAX_MACS):0] data_count;
    wire [$clog2(MAX_MACS):0] total_macs;

    // 索引变量
    reg [MAX_ADDR_WIDTH-1:0] idx1_out;

    // 输出尺寸
    wire [ADDR_WIDTH-1:0] out_row, out_col;
    assign out_row = img_row_reg - ker_row_reg + 1;
    assign out_col = img_col_reg - ker_col_reg + 1;

    // 卷积索引
    reg [ADDR_WIDTH-1:0] conv_row;
    reg [ADDR_WIDTH-1:0] conv_col;
    reg [ADDR_WIDTH-1:0] for_conv_row;
    reg [ADDR_WIDTH-1:0] for_conv_col;

    // SRAM OUTPUT DATA
    wire signed [MAX_DATA_WIDTH-1:0] gemm0_data_out;
    wire signed [MAX_DATA_WIDTH-1:0] gemm1_data_out;
    wire signed [2*MAX_DATA_WIDTH-1:0] elem_data_out;
    wire signed [2*MAX_DATA_WIDTH-1:0] sram_data_out;



    // get img and kernel size from axi_stream_input
    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn) begin
            img_row_reg <= 0;
            img_col_reg <= 0;
            ker_row_reg <= 0;
            ker_col_reg <= 0;
        end else begin
            if (data_ready && data_type == GEMM0_SRAM_IDX) begin
                img_row_reg <= img_row;
                img_col_reg <= img_col;
            end else if (data_ready && data_type == GEMM1_SRAM_IDX) begin
                ker_row_reg <= ker_row;
                ker_col_reg <= ker_col;
            end
        end
    end

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
                if (conv_row >= out_row - 1 && conv_col >= out_col - 1 && for_conv_col >= ker_col_reg)
                    next_state = WAIT_LAST;
                else if (for_conv_col == ker_col_reg )
                    next_state = COMPUTE_CONV1;
                else
                    next_state = COMPUTE_CONV0;
            end
            COMPUTE_CONV1: begin
                next_state = COMPUTE_CONV0;
            end
            WAIT_LAST: begin
                if (mac_valid_out)
                    next_state = WRITE_OUTPUT;
            end
            WRITE_OUTPUT: begin
                if (sram_out_addr >= out_row * out_col)begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn)
            state <= IDLE;
        else
            state <= next_state;
    end

    

    // control convolution index
    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn) begin
            conv_row <= 0;
            conv_col <= 0;
            for_conv_row <= 0;
            for_conv_col <= 0;
            idx1_out <= 0;
        end else if (state == COMPUTE_CONV0) begin
            if (for_conv_row < ker_row_reg - 1 || for_conv_col < ker_col_reg - 1) begin
                if (for_conv_col < ker_col_reg - 1) begin
                    for_conv_col <= for_conv_col + 1;
                end else begin
                    for_conv_col <= 0;
                    if (for_conv_row < ker_row_reg - 1) begin
                        for_conv_row <= for_conv_row + 1;
                    end
                end
            end else if(for_conv_row == ker_row_reg-1 && for_conv_col == ker_col_reg-1) begin
                for_conv_col <= for_conv_col + 1;
            end else begin
                for_conv_row <= 0;
                for_conv_col <= 0;
                if (conv_col < out_col - 1) begin
                    conv_col <= conv_col + 1;
                end else begin
                    conv_col <= 0;
                    if (conv_row < out_row - 1) begin
                        conv_row <= conv_row + 1;
                    end else begin
                        conv_row <= 0;
                    end
                end
            end
        end
    end

    // control mac_valid_in
    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn) begin
            mac_valid_in <= 1'b0;
        end else if (state == COMPUTE_CONV0 && data_count == total_macs-1) begin
            mac_valid_in <= 1'b1;
        end else begin
            mac_valid_in <= 1'b0;
        end
    end

    assign num_macs_i = ker_row_reg * ker_col_reg;
    assign total_macs = num_macs_i;


    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn || state != COMPUTE_CONV0) begin
            data_mac_i <= 0;
            weight_mac_i <= 0;
            data_count <= 0;
        end else if (state == COMPUTE_CONV0) begin
            integer idx;
            idx = for_conv_row * ker_col_reg + for_conv_col;
            if (idx && idx <= total_macs) begin
                data_mac_i[(idx-1) * C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] <= gemm0_data_out;
                weight_mac_i[(idx-1) * C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] <= gemm1_data_out;
                data_count <= data_count + 1;
            end
        end
    end

    // 控制结果索引
    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn) begin
            idx1_out <= 0;
        end else if (mac_valid_out) begin
            idx1_out <= idx1_out + 1;
        end
    end

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
        .out_size(out_row * out_col)
    );

    sram_controller
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        // GEMM1 port
        .gemm1_addr((conv_row + for_conv_row) * img_col_reg + conv_col + for_conv_col),
        .gemm1_data_in(),
        .gemm1_en(state == COMPUTE_CONV0),
        .gemm1_we(1'b0),
        .gemm1_idx(GEMM0_SRAM_IDX),
        .gemm1_data_out(gemm0_data_out),
        // GEMM2 port
        .gemm2_addr(for_conv_row * ker_col_reg + for_conv_col),
        .gemm2_data_in(),
        .gemm2_en(state == COMPUTE_CONV0),
        .gemm2_we(1'b0),
        .gemm2_idx(GEMM1_SRAM_IDX),
        .gemm2_data_out(gemm1_data_out),
        // ELEM port
        .elem_addr(idx1_out),
        .elem_data_in(mac_out),
        .elem_en(mac_valid_out),
        .elem_we(mac_valid_out),
        .elem_idx(ELEM0_SRAM_IDX),
        .elem_data_out(elem_data_out),
        // axi4 input port
        .write_address(write_address),
        .write_data(write_data),
        .axi_idx(data_type),
        .write_enable(write_enable),
        // axi4 output port
        .sram_out_en(sram_out_en),
        .sram_out_idx(ELEM0_SRAM_IDX),
        .sram_out_addr(sram_out_addr),
        .sram_out_data(sram_data_out)
    );

    mac #
    (
        .MAX_MACS(MAX_MACS),
        .DATA_WIDTH(C_AXIS_TDATA_WIDTH)
    )
    mac_gen (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .num_macs_i(num_macs_i),
        .valid_in(mac_valid_in),
        .data(data_mac_i),
        .weight(weight_mac_i),
        .mac_out(mac_out),
        .valid_out(mac_valid_out)
    );
endmodule
