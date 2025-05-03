// 目前的問題是axi_stream_output的tvalid跟start_output不一樣導致addr錯誤, 取到錯的data, 還有存入sram的data有幾個也是錯的需要去debug
`timescale 1ns / 1ps
`include "params.vh"
// ---------------------------------------------
// op code
// 4'b0000: No operation -> idle
// 4'b0001: Conv
// 4'b0010: Fc
// 4'b0011: Exp
// 4'b0100: Reciprocal
// 4'b0101: ADD
// 4'b0110: SUB
// 4'b0111: MUL
// ------------------------------------------------
module npu #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 64,
    parameter C_AXIS_MDATA_WIDTH = 64,
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
    output wire signed [C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output wire [(C_AXIS_MDATA_WIDTH/8)-1 : 0]   m00_axis_tstrb, 
    output wire                   m00_axis_tvalid,
    input  wire                   m00_axis_tready,
    output wire                   m00_axis_tlast,
    output wire [NUM_CHANNELS_WIDTH-1:0]           m00_axis_tuser, 

    // convolution signals
    input wire [ADDR_WIDTH-1:0] batch,
    input wire [ADDR_WIDTH-1:0] img_row,
    input wire [ADDR_WIDTH-1:0] img_col,
    input wire [ADDR_WIDTH-1:0] ker_row,
    input wire [ADDR_WIDTH-1:0] ker_col,
    input wire [3:0]            stride_h,
    input wire [3:0]            stride_w,
    input wire [ADDR_WIDTH-1:0] in_channel,
    input wire [ADDR_WIDTH-1:0] out_channel,
    input wire                   padding,

    // MUL signals
    input wire signed [INT32_SIZE-1:0] mul_input1_offset,
    input wire signed [INT32_SIZE-1:0] mul_input2_offset,
    input wire  [INT32_SIZE-1:0] mul_output_multiplier,
    input wire signed [INT32_SIZE-1:0] mul_output_shift,
    input wire signed [INT32_SIZE-1:0] mul_output_offset,
    input wire signed [31:0] mul_quantized_activation_min,
    input wire signed [31:0] mul_quantized_activation_max,

    // ADD signals
    input wire signed [INT32_SIZE-1:0] add_input1_offset,
    input wire signed [INT32_SIZE-1:0] add_input2_offset,
    input wire signed [INT32_SIZE-1:0] add_left_shift,
    input wire  [INT32_SIZE-1:0] add_input1_multiplier,
    input wire  [INT32_SIZE-1:0] add_input2_multiplier,
    input wire signed [INT32_SIZE-1:0] add_input1_shift,
    input wire signed [INT32_SIZE-1:0] add_input2_shift,
    input wire  [INT32_SIZE-1:0] add_output_multiplier,
    input wire signed [INT32_SIZE-1:0] add_output_shift,
    input wire signed [INT32_SIZE-1:0] add_output_offset,
    input wire signed [31:0] add_quantized_activation_min,
    input wire signed [31:0] add_quantized_activation_max,

    // SUB signals
    input wire signed [INT32_SIZE-1:0] sub_input1_offset,
    input wire signed [INT32_SIZE-1:0] sub_input2_offset,
    input wire signed [INT32_SIZE-1:0] sub_left_shift,
    input wire  [INT32_SIZE-1:0] sub_input1_multiplier,
    input wire  [INT32_SIZE-1:0] sub_input2_multiplier,
    input wire signed [INT32_SIZE-1:0] sub_input1_shift,
    input wire signed [INT32_SIZE-1:0] sub_input2_shift,
    input wire  [INT32_SIZE-1:0] sub_output_multiplier,
    input wire signed [INT32_SIZE-1:0] sub_output_shift,
    input wire signed [INT32_SIZE-1:0] sub_output_offset,
    input wire signed [31:0] sub_quantized_activation_min,
    input wire signed [31:0] sub_quantized_activation_max,

    // conv or fc requant signals
    input wire [31:0]             quantized_multiplier,
    input wire signed  [31:0]     shift,
    input wire signed  [31:0]     gemm_output_offset,

    // dequant && requant signals(zero_point, range_radius) for exp
    input signed  [31:0]            exp_deq_input_zero_point,
    input signed  [31:0]            exp_deq_input_range_radius,
    input signed  [31:0]            exp_deq_input_left_shift,
    input   [31:0]            exp_deq_input_multiplier, 
    input   [31:0]            exp_req_input_quantized_multiplier,
    input signed  [31:0]            exp_req_input_shift,
    input signed  [31:0]            exp_req_input_offset,

    // dequant && requant signals for reciprocal
    input signed  [31:0]            reciprocal_deq_input_zero_point,
    input signed  [31:0]            reciprocal_deq_input_range_radius,
    input signed  [31:0]            reciprocal_deq_input_left_shift,
    input   [31:0]            reciprocal_deq_input_multiplier,
    input   [31:0]            reciprocal_req_input_quantized_multiplier,
    input signed  [31:0]            reciprocal_req_input_shift,  
    input signed  [31:0]            reciprocal_req_input_offset,
    // -------------------------------------
    // WAIT_META state
    // send metadata & kernel...

    input wire [3:0] op,
    input wire metadata_valid_i,
    input wire finish_calc,
    // input 
    // weight block number send from npu(testbench)
    input wire [2:0] weight_num,
    // sram address and op4, 3bits means 8 operations and there are sequential operations
    input [2:0] store_sram_idx0,
    // weight store sram idx
    input wire [2:0] op0_weight_sram_idx0,
    input wire [2:0] op0_weight_sram_idx1,
    // op broadcast? 0 means no, 1 means sram0, 2 means sram1 that need to broadcast data
    input wire [2:0] op0_broadcast,
    input wire metadata_done,
    // op weight & data counts that store in buffer
    input wire [31:0] op0_weight_total_counts,
    input wire [31:0] op0_input_data_total_counts,
    // -------------------------------------
    // output for that layer finish calculation for OP_DONE
    output reg layer_calc_done,
    // -------------------------------------
    // defferent op counts that need to calculate
    input wire [MAX_ADDR_WIDTH-1:0] op0_data_counts,
    // -------------------------------------
    // output for cycles
    output reg [31:0] cycle_count,
    output wire [31:0] sram_access_counts,
    output reg [31:0] dram_access_counts
);
    // memory access counts
    wire [31:0] total_mem_access_counts;
    assign sram_access_counts = total_mem_access_counts - dram_access_counts;
    reg [2:0] state = IDLE, next_state;
    // axi_stream_input signals
    wire                    write_enable;
    wire [MAX_ADDR_WIDTH-1:0]   write_address;
    wire signed [C_AXIS_TDATA_WIDTH-1:0] write_data;
    wire [2:0]              data_type;
    wire                    data_ready;
    // wire [ADDR_WIDTH-1:0]   img_row;
    // wire [ADDR_WIDTH-1:0]   img_col;
    // wire [ADDR_WIDTH-1:0]   ker_row;
    // wire [ADDR_WIDTH-1:0]   ker_col;
    wire [NUM_CHANNELS_WIDTH-1:0] num_channels;
    // wire [3:0]             stride_h, stride_w;
    // wire [ADDR_WIDTH-1:0]   in_channel, out_channel;
    // wire                    padding ;
    wire [5:0]              input_data_idx;
    // wire [ADDR_WIDTH-1:0]   batch;
    wire [2:0]              weight_num_reg;  


    // axi_stream_output signals
    wire                   sram_out_en;
    wire [MAX_ADDR_WIDTH-1:0]  sram_out_addr;
    wire [MAX_ADDR_WIDTH-1:0]  out_size;

    // convolution signals
    wire signed [C_AXIS_MDATA_WIDTH - 1 : 0] GEMM_out;
    wire mac_valid_out;

    // output index control (elementwise and GEMM)
    wire [MAX_ADDR_WIDTH-1:0] GEMM_results_counts, ele_results_counts, cur_counts,ele_valid_in_counts;
    assign cur_counts = (op == CONV_OP || op == FC_OP)? GEMM_results_counts : MAX_VECTOR_SIZE * ele_results_counts;

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
    wire signed [SRAM_WIDTH_O-1:0] op0_weight_sram_data_o;
    wire signed [SRAM_WIDTH_O-1:0] op0_data_sram_data_o;
    reg signed [SRAM_WIDTH_O-1:0] op0_weight_sram_data_o_delay, op0_data_sram_data_o_delay;

    // SRAM controller signals
    wire op0_data_sram_en;
    reg op0_data_sram_en_delay;
    wire [MAX_ADDR_WIDTH-1:0] op0_data_addr_o;
    reg [MAX_ADDR_WIDTH-1:0] op0_data_addr_o_delay;
    // requant signals
    wire GEMM_valid_o;

    // element_wise signals
    reg GEMM_en, exp_en, reciprocal_en, add_en, sub_en, mul_en;
    wire signed [C_AXIS_TDATA_WIDTH-1:0] element_wise_data_o;
    wire element_wise_valid_o;
    wire [17:0] element_wise_idx_o;
    wire ele_valid_o;
    wire [INT64_SIZE-1:0] ele_data_o;

    // repacker signals
    wire repacker_last, repacker_valid_out;
    wire [7:0] valid_mask;
    wire [INT64_SIZE-1:0] repacker_data_out, repacker_data_i;
    reg [MAX_ADDR_WIDTH-1:0] repacker_output_index;

    // broadcast unit signals
    wire broadcast_valid_i, broadcast_en, broadcast_valid_o;
    wire [MAX_ADDR_WIDTH-1:0] broadcast_addr_i;
    wire [MAX_VECTOR_SIZE * INT8_SIZE-1:0] broadcast_data_i, broadcast_data_o;
    wire [INT32_SIZE-1:0] broadcast_number_of_elements_i;
    assign broadcast_number_of_elements_i = (op0_broadcast == 3'd2)? op0_weight_total_counts:
                                            (op0_broadcast == 3'd1)? op0_input_data_total_counts: 1'b0;
    assign broadcast_data_i = (op0_broadcast == 3'd2)? op0_weight_sram_data_o:
                              (op0_broadcast == 3'd1)? op0_data_sram_data_o: 1'b0;
    assign broadcast_addr_i = (op0_broadcast == 3'd2)? op0_data_addr_o_delay:
                              (op0_broadcast == 3'd1)? op0_data_addr_o_delay: 1'b0;
    assign broadcast_en = (op0_broadcast > 0 && op0_data_sram_en_delay)? 1'b1: 1'b0;
    assign broadcast_valid_i = (op0_broadcast == 3'd1 && broadcast_en)? op0_data_addr_o_delay < op0_input_data_total_counts:
                               (op0_broadcast == 3'd2 && broadcast_en)? op0_data_addr_o_delay < op0_weight_total_counts: 1'b0;

    // Enable different engines
    always @(*) begin
        GEMM_en = ((op == CONV_OP || op == FC_OP) && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
        exp_en = (op == EXP_OP && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
        reciprocal_en = (op == RECIPROCAL_OP && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
        add_en = (op == ADD_OP && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
        sub_en = (op == SUB_OP && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
        mul_en = (op == MUL_OP && state == WAIT_OP && MAX_VECTOR_SIZE*ele_valid_in_counts < op0_data_counts)? 1'b1 : 1'b0;
    end
    // control FSM
    // always @(*) begin
    //     next_state = state;
    //     case (state)
    //         IDLE: begin
    //             if (data_ready && data_type == GEMM0_SRAM_IDX)
    //                 next_state = LOAD_IMG;
    //         end
    //         LOAD_IMG: begin
    //             if (data_ready && data_type == GEMM1_SRAM_IDX)
    //                 next_state = LOAD_KER;
    //         end
    //         LOAD_KER: begin
    //             // assum that the data is ready
    //             if (!data_ready)
    //                 next_state = COMPUTE_CONV0;
    //         end
    //         COMPUTE_CONV0: begin
    //             next_state = (start_output)? WRITE_OUTPUT : COMPUTE_CONV0;
    //         end
    //         WRITE_OUTPUT: begin
    //             if (sram_out_addr >= out_size)begin
    //                 next_state = IDLE;
    //             end 
    //         end
    //         default: next_state = IDLE;
    //     endcase
    // end
    always @(*)begin
        next_state = state;
        case (state)
            IDLE: begin
                if (metadata_valid_i)
                    next_state = WAIT_META;
            end
            WAIT_META: begin
                if (metadata_done && weight_num_reg == 0)
                    next_state = WAIT_OP;
                else if(finish_calc)
                    next_state = WRITE_OUTPUT;
                else 
                    next_state = WAIT_META;
            end
            WAIT_OP: begin
                // assum that the data is ready
                // if (!data_ready)
                if( cur_counts >= op0_data_counts)
                    next_state = OP_DONE;
            end
            OP_DONE: begin
                next_state = WAIT_META;
            end
            WRITE_OUTPUT: begin
                if (sram_out_addr >= out_size)begin
                    next_state = IDLE;
                end 
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge s00_axis_aclk or negedge s00_axis_aresetn) begin
        if (!s00_axis_aresetn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            layer_calc_done <= 1'b0;
        end else if(state == OP_DONE) begin
            layer_calc_done <= 1'b1;
        end else begin
            layer_calc_done <= 1'b0;
        end
    end
    GEMM #
    (
        .MAX_MACS(MAX_MACS),
        .ADDR_WIDTH(ADDR_WIDTH)
    )
    GEMM_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .init(state == OP_DONE),
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
        .GEMM_out(GEMM_out),
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
        .output_offset(gemm_output_offset),
        .GEMM_valid_o(GEMM_valid_o),
        .GEMM_results_counts(GEMM_results_counts)
    );
    wire [SRAM_WIDTH_O-1:0] ele_data_in_sel, ele_weight_in_sel;
    assign ele_data_in_sel = (op0_broadcast == 3'd1)? broadcast_data_o:
                             (op0_broadcast == 3'd2)? op0_data_sram_data_o_delay:
                                                      op0_data_sram_data_o;
    assign ele_weight_in_sel = (op0_broadcast == 3'd2)? broadcast_data_o:
                               (op0_broadcast == 3'd1)? op0_weight_sram_data_o_delay:
                                                        op0_weight_sram_data_o;

    element_wise element_wise_gen
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .init(state == OP_DONE),
        .broadcast(op0_broadcast),
        .exp_en(exp_en),
        .reciprocal_en(reciprocal_en),
        .add_en(add_en),
        .sub_en(sub_en),
        .mul_en(mul_en),
        .data_in(ele_data_in_sel),
        .weight_data_in(ele_weight_in_sel),
        .output_data_counts_i(op0_data_counts),
        // .valid_in(element_wise_exp_en_delay),
        .exp_deq_input_left_shift(exp_deq_input_left_shift),
        .exp_deq_input_zero_point(exp_deq_input_zero_point),
        .exp_deq_input_range_radius(exp_deq_input_range_radius),
        .exp_deq_input_multiplier(exp_deq_input_multiplier),
        .exp_req_input_quantized_multiplier(exp_req_input_quantized_multiplier),
        .exp_req_input_shift(exp_req_input_shift),
        .exp_req_input_offset(exp_req_input_offset),
        .reciprocal_deq_input_left_shift(reciprocal_deq_input_left_shift),
        .reciprocal_deq_input_zero_point(reciprocal_deq_input_zero_point),
        .reciprocal_deq_input_range_radius(reciprocal_deq_input_range_radius),
        .reciprocal_deq_input_multiplier(reciprocal_deq_input_multiplier),
        .reciprocal_req_input_quantized_multiplier(reciprocal_req_input_quantized_multiplier),
        .reciprocal_req_input_shift(reciprocal_req_input_shift),
        .reciprocal_req_input_offset(reciprocal_req_input_offset),
        .add_input1_offset(add_input1_offset),
        .add_input2_offset(add_input2_offset),
        .add_left_shift(add_left_shift),
        .add_input1_multiplier(add_input1_multiplier),
        .add_input2_multiplier(add_input2_multiplier),
        .add_input1_shift(add_input1_shift),
        .add_input2_shift(add_input2_shift),
        .add_output_multiplier(add_output_multiplier),
        .add_output_shift(add_output_shift),
        .add_output_offset(add_output_offset),
        .add_quantized_activation_min(add_quantized_activation_min),
        .add_quantized_activation_max(add_quantized_activation_max),
        .sub_input1_offset(sub_input1_offset),
        .sub_input2_offset(sub_input2_offset),
        .sub_left_shift(sub_left_shift),
        .sub_input1_multiplier(sub_input1_multiplier),
        .sub_input2_multiplier(sub_input2_multiplier),
        .sub_input1_shift(sub_input1_shift),
        .sub_input2_shift(sub_input2_shift),
        .sub_output_multiplier(sub_output_multiplier),
        .sub_output_shift(sub_output_shift),
        .sub_output_offset(sub_output_offset),
        .sub_quantized_activation_min(sub_quantized_activation_min),
        .sub_quantized_activation_max(sub_quantized_activation_max),
        .mul_input1_offset(mul_input1_offset),
        .mul_input2_offset(mul_input2_offset),
        .mul_output_multiplier(mul_output_multiplier),
        .mul_output_shift(mul_output_shift),
        .mul_output_offset(mul_output_offset),
        .mul_quantized_activation_min(mul_quantized_activation_min),
        .mul_quantized_activation_max(mul_quantized_activation_max),
        // sram control signals
        .ele_data_addr_o(op0_data_addr_o),
        .ele_sram_en(op0_data_sram_en),
        // --------------------
        .ele_data_out(ele_data_o),
        .ele_valid_out(ele_valid_o),
        .ele_valid_in_counts(ele_valid_in_counts),
        .ele_results_counts(ele_results_counts)
    ); 

    broadcast_unit broadcast_unit_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .valid_i(broadcast_valid_i),
        .init(state == OP_DONE),
        .en(broadcast_en),
        .data_i(broadcast_data_i),
        .addr_i(broadcast_addr_i),
        .number_of_elements_i(broadcast_number_of_elements_i),
        .valid_o(broadcast_valid_o),
        .data_o(broadcast_data_o)
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
        // WAIT_META  state signals
        .metadata_valid_i(metadata_valid_i),
        .op0_weight_sram_idx0(op0_weight_sram_idx0),
        .op0_weight_sram_idx1(op0_weight_sram_idx1),
        .weight_num(weight_num),
        .weight_num_reg_o(weight_num_reg),
        // .img_row(img_row),
        // .img_col(img_col),
        // .ker_row(ker_row),
        // .ker_col(ker_col),
        // .batch(batch),
        // .stride_h(stride_h),
        // .stride_w(stride_w),
        // .in_channel(in_channel),
        // .output_channel(out_channel),
        // .padding(padding),
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
        .groups(4'd8)
    );
    wire [MAX_ADDR_WIDTH-1:0] gemm1_addr_i;
    // assign gemm1_addr_i = (conv_col * img_row + conv_row) * in_channel + input_data_idx;
    assign gemm1_addr_i = (ker_col == 1'b1 && ker_row == 1'b1)? (conv_col * img_row + conv_row) * in_channel + input_data_idx :
                        (((conv_col + for_conv_col) * img_row) + conv_row ) * in_channel + (input_data_cur_idx - for_conv_col * patch);
    // store output to sram signals sel
    wire  result_sram_en_sel, result_sram_we_sel;
    wire [MAX_ADDR_WIDTH-1:0] result_sram_addr_i_sel;
    wire [INT64_SIZE-1:0] result_sram_data_i_sel;
    assign result_sram_en_sel = repacker_valid_out | ele_valid_o; // repacker_valid_out -> GEMM的運算結果會存在repacker, 然後滿8比才輸出
    assign result_sram_we_sel = repacker_valid_out | ele_valid_o;
    assign result_sram_data_i_sel = (op == CONV_OP || op == FC_OP)? repacker_data_out : 
                                                    ele_data_o;
    assign result_sram_addr_i_sel = (repacker_valid_out)? repacker_output_index : 
                                                          ele_results_counts;
                                                        //   ele_data_addr_o;
    wire gemm_en;
    assign gemm_en = ((op == CONV_OP || op == FC_OP) && state == WAIT_OP )? 1'b1 : 1'b0;
    sram_controller sram_controller_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        // GEMM1 port
        .gemm1_addr(gemm1_addr_i),
        .gemm1_data_in(),
        .gemm1_en(gemm_en),
        .gemm1_we(1'b0),
        .gemm1_idx(op0_weight_sram_idx1),
        .gemm1_data_out(gemm0_data_out),
        // GEMM2 port
        .gemm2_addr(weight_idx),
        .gemm2_data_in(),
        .gemm2_en(gemm_en),
        .gemm2_we(1'b0),
        .gemm2_idx(op0_weight_sram_idx0),
        .gemm2_data_out(gemm1_data_out),
        // ELEM0  port
        .elem_addr(),
        .elem_data_in(GEMM_out),
        // .elem_en(mac_valid_out),
        // .elem_we(mac_valid_out),
        .elem_en(),
        .elem_we(GEMM_valid_o),
        .elem_idx(ELEM0_SRAM_IDX),
        .elem_data_out(elem_data_out),
        // axi4 input port
        .write_address(write_address),
        .write_data(write_data),
        .axi_idx(data_type),
        .write_enable(write_enable),
        // axi4 output port
        .sram_out_en(sram_out_en),
        .sram_out_idx(store_sram_idx0),
        .sram_out_addr(sram_out_addr),
        .sram_out_data(sram_data_out),
        // op0 weight access sram
        .op0_weight_sram_en(op0_data_sram_en),
        .op0_weight_sram_addr_i(op0_data_addr_o),
        .op0_weight_sram_idx(op0_weight_sram_idx0),
        .op0_weight_sram_data_o(op0_weight_sram_data_o),
        // op0 data access sram
        .op0_data_sram_en(op0_data_sram_en),
        .op0_data_sram_addr_i(op0_data_addr_o),
        .op0_data_sram_idx(op0_weight_sram_idx1),
        .op0_data_sram_data_o(op0_data_sram_data_o),
        // store op result to sram
        .result_sram_en(result_sram_en_sel),
        .result_sram_we(result_sram_en_sel),
        .result_sram_addr_i(result_sram_addr_i_sel),
        .result_sram_data_i(result_sram_data_i_sel),
        .result_sram_idx(store_sram_idx0),
        // total memoory access counts
        .total_mem_access_counts(total_mem_access_counts)
    );

    assign valid_mask = 8'b1;
    assign repacker_data_i = { 56'b0, GEMM_out[7:0]};
    assign repacker_last = (GEMM_results_counts >= op0_data_counts)? 1'b1 : 1'b0;
    repacker #
    (
        .OUTPUT_WIDTH(64),
        .TOTAL_BTYES(8),
        .ACCU_WIDTH(128)
    ) repacker_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .in_valid(GEMM_valid_o),
        .data_i(repacker_data_i),
        .valid_mask(valid_mask),
        .tlast_i(repacker_last),
        .out_valid(repacker_valid_out),
        .data_o(repacker_data_out)
    );
    // delay 1 cycle due to broadcast_unit will delay
    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            op0_data_addr_o_delay <= 0;
        end else begin
            op0_data_addr_o_delay <= op0_data_addr_o;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            op0_weight_sram_data_o_delay <= 0;
        end else begin
            op0_weight_sram_data_o_delay <= op0_weight_sram_data_o;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            op0_data_sram_data_o_delay <= 0;
        end else begin
            op0_data_sram_data_o_delay <= op0_data_sram_data_o;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            op0_data_sram_en_delay <= 0;
        end else begin
            op0_data_sram_en_delay <= op0_data_sram_en;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            repacker_output_index <= 0;
        end else if(repacker_valid_out) begin
            repacker_output_index <= repacker_output_index + 1;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn)begin
            dram_access_counts <= 0;
        end else if(state == WRITE_OUTPUT || write_enable)begin
            dram_access_counts <= dram_access_counts + 1;
        end
    end

    // cycle count control
    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            cycle_count <= 0;
        end else if(state == WAIT_OP)begin
            cycle_count <= cycle_count + 1;
        end
    end 

    // DEBUG
endmodule
