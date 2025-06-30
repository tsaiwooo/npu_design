`timescale 1ns / 1ps
`include "params.vh"
// --------------------------
// state machine
// metadata transfer -> load img or kernel -> compute & load result
// --------------------------
module npu #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 64,
    parameter C_AXIS_MDATA_WIDTH = 64,
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1),
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

    // requant signals
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
    input wire metadata_valid_i,
    input wire finish_calc,
    input [15:0] op,
    // input 
    // weight block number send from npu(testbench)
    input wire [2:0] weight_num,
    // sram address and op4, 3bits means 8 operations and there are sequential operations
    input [2:0] store_sram_idx0,
    // weight store sram idx
    input wire [2:0] op0_weight_sram_idx0,
    input wire [2:0] op0_weight_sram_idx1,
    input wire [2:0] op1_weight_sram_idx0,
    input wire [2:0] op2_weight_sram_idx0,
    input wire [2:0] op3_weight_sram_idx0,
    // op broadcast? 0 means no, 1 means yes
    input wire [2:0] op0_broadcast,
    input wire [2:0] op1_broadcast,
    input wire [2:0] op2_broadcast,
    input wire [2:0] op3_broadcast,
    input wire metadata_done,
    // op weight & data counts that store in buffer
    input wire [31:0] op0_weight_total_counts,
    input wire [31:0] op0_input_data_total_counts,
    input wire [31:0] op1_weight_total_counts,
    input wire [31:0] op2_weight_total_counts,
    input wire [31:0] op3_weight_total_counts,
    // -------------------------------------
    // output for that layer finish calculation for OP_DONE
    output reg layer_calc_done,
    // -------------------------------------
    // defferent op counts that need to calculate
    input wire [MAX_ADDR_WIDTH-1:0] op0_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op1_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op2_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op3_data_counts,
    // -------------------------------------
    // // output for cycles
    output reg [63:0] cycle_count,
    output wire [63:0] sram_access_counts,
    output reg [63:0] dram_access_counts,
    output reg [63:0] elementwise_idle_counts
);
    // AXI4-Lite slave interface signals
    // input  wire         axi_aclk,
    // input  wire         axi_aresetn,
    // // Write address channel
    // input  wire [31:0]  S_AXI_AWADDR,
    // input  wire         S_AXI_AWVALID,
    // output reg          S_AXI_AWREADY,
    // // Write data channel
    // input  wire [31:0]  S_AXI_WDATA,
    // input  wire [3:0]   S_AXI_WSTRB,
    // input  wire         S_AXI_WVALID,
    // output reg          S_AXI_WREADY,
    // // Write response channel
    // output reg [1:0]    S_AXI_BRESP,
    // output reg          S_AXI_BVALID,
    // input  wire         S_AXI_BREADY,
    // // Read address channel
    // input  wire [31:0]  S_AXI_ARADDR,
    // input  wire         S_AXI_ARVALID,
    // output reg          S_AXI_ARREADY,
    // // Read data channel
    // output reg [31:0]   S_AXI_RDATA,
    // output reg [1:0]    S_AXI_RRESP,
    // output reg          S_AXI_RVALID,
    // input  wire         S_AXI_RREADY,
    // memory access counts
    wire [63:0] total_mem_access_counts, store_access_sram_counts;
    // assign sram_access_counts = total_mem_access_counts - dram_access_counts;
    assign sram_access_counts = store_access_sram_counts;
    // op_decoder signals
    wire conv_en, fc_en, exp_en, reciprocal_en, add_en, sub_en, mul_en;
    wire [INT64_SIZE-1:0] conv_data_in, fc_data_in, exp_data_in, reciprocal_data_in, add_data_in, sub_data_in, mul_data_in;
    wire [INT64_SIZE-1:0] conv_data_out, fc_data_out, exp_data_out, reciprocal_data_out, add_data_out, sub_data_out, mul_data_out;
    wire conv_valid_out, fc_valid_out, exp_valid_out, reciprocal_valid_out, add_valid_out, sub_valid_out, mul_valid_out;
    wire store_to_sram_en;
    wire [INT64_SIZE-1:0] store_to_sram_data;
    wire op0_data_sram_en, op1_data_sram_en, op2_data_sram_en, op3_data_sram_en;
    wire [MAX_ADDR_WIDTH-1:0]  op0_weight_addr_o,op0_data_addr_o,op1_weight_addr_o,op2_weight_addr_o,op3_weight_addr_o;
    wire [INT64_SIZE-1:0] op0_weight_sram_data_o,op0_data_sram_data_o,op1_weight_sram_data_o,op2_weight_sram_data_o,op3_weight_sram_data_o;
    wire [C_AXIS_MDATA_WIDTH-1:0] add_weight_i,sub_weight_i,mul_weight_i;
    wire [MAX_ADDR_WIDTH-1:0] op_total_data_counts,expected_total_data_counts;


    reg [2:0] state = IDLE, next_state;
    reg GEMM_en = 1'b0;
    reg ELEMENT_en = 1'b0;

    // axi_stream_input signals
    wire                    write_enable;
    wire [MAX_ADDR_WIDTH-1:0]   write_address;
    wire signed [C_AXIS_TDATA_WIDTH-1:0] write_data;
    wire [2:0]              data_type;
    wire                    data_ready;

    wire [NUM_CHANNELS_WIDTH-1:0] num_channels;

    wire [MAX_ADDR_WIDTH-1:0]              input_data_idx;
    wire [2:0]              weight_num_reg;


    // axi_stream_output signals
    wire                   sram_out_en;
    wire [MAX_ADDR_WIDTH-1:0]  sram_out_addr;
    wire [MAX_ADDR_WIDTH-1:0]  out_size;

    // convolution signalsz
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

    // sram_controller signals
    wire [MAX_ADDR_WIDTH-1:0] gemm1_addr_i;
    // assign gemm1_addr_i = (conv_col * img_row + conv_row) * in_channel + input_data_idx;
    assign gemm1_addr_i = (ker_col == 1'b1 && ker_row == 1'b1)? (conv_col * img_row + conv_row) * in_channel + input_data_idx :
                        (((conv_col + for_conv_col) * img_row) + conv_row ) * in_channel + (input_data_cur_idx - for_conv_col * patch);

    // SRAM OUTPUT DATA
    wire signed [SRAM_WIDTH_O-1:0] gemm0_data_out;
    wire signed [SRAM_WIDTH_O-1:0] gemm1_data_out;
    wire signed [SRAM_WIDTH_O-1:0] elem_data_out;
    wire signed [SRAM_WIDTH_O-1:0] sram_data_out;

    // requant signals
    wire requant_valid_o;

    // GEMM output of stored_num_groups_o
    wire [3:0] stored_num_groups_o,groups;
    assign groups = (op[3:0] == 4'b0001)? stored_num_groups_o :
                    (op[3:0] == 4'b0010)? stored_num_groups_o : 4'd8;

    // repacker signals
    wire [INT64_SIZE-1:0] repacker_data_out;
    wire repacker_valid_out;
    reg [MAX_ADDR_WIDTH-1:0] repaker_output_index;


    assign m00_axis_tstrb = groups;

    // element-wise signals
    // -------------------------------------
    // exp
    // -------------------------------------
    wire [MAX_VECTOR_SIZE * C_AXIS_MDATA_WIDTH - 1:0] exp_data_o;
    wire exp_valid_o;

    // broadcast unit signals
    reg op0_data_sram_en_delay, op1_data_sram_en_delay, op2_data_sram_en_delay, op3_data_sram_en_delay;
    reg [MAX_ADDR_WIDTH-1:0] op0_weight_addr_o_delay,op1_weight_addr_o_delay,op2_weight_addr_o_delay,op3_weight_addr_o_delay,op0_data_addr_o_delay;
    wire broadcast_valid_i, broadcast_en, broadcast_valid_o;
    wire [MAX_ADDR_WIDTH-1:0] broadcast_addr_i;
    wire [MAX_VECTOR_SIZE*INT8_SIZE-1:0] broadcast_data_i, broadcast_data_o;
    wire [INT32_SIZE-1:0] broadcast_number_of_elements_i;
    wire [INT64_SIZE-1:0] op0_data_sram_data_i, op0_weight_sram_data_i, op1_weight_sram_data_i, op2_weight_sram_data_i, op3_weight_sram_data_i;
    reg [INT64_SIZE-1:0] op0_data_sram_data_i_reg, op0_weight_sram_data_i_reg, op1_weight_sram_data_i_reg, op2_weight_sram_data_i_reg, op3_weight_sram_data_i_reg;
    assign broadcast_valid_i = (op0_broadcast == 2'd1 && broadcast_en)? op0_weight_addr_o_delay < op0_weight_total_counts :
                               (op0_broadcast == 2'd2 && broadcast_en)? op0_data_addr_o_delay < op0_input_data_total_counts :
                               (op1_broadcast == 2'd1 && broadcast_en)? op1_weight_addr_o_delay < op1_weight_total_counts :
                               (op2_broadcast == 2'd1 && broadcast_en)? op2_weight_addr_o_delay < op2_weight_total_counts :
                               (op3_broadcast == 2'd1 && broadcast_en)? op3_weight_addr_o_delay < op3_weight_total_counts : 1'b0;
    assign broadcast_en = (op0_broadcast > 0 && op0_data_sram_en_delay)?  1'b1 :
                          (op1_broadcast > 0 && op1_data_sram_en_delay)?  1'b1 :
                          (op2_broadcast > 0 && op2_data_sram_en_delay)?  1'b1 :
                          (op3_broadcast > 0 && op3_data_sram_en_delay)?  1'b1 : 1'b0;
    assign broadcast_addr_i = (op0_broadcast == 2'd1)? op0_weight_addr_o_delay :
                              (op0_broadcast == 2'd2)? op0_data_addr_o_delay :
                              (op1_broadcast == 2'd1)? op1_weight_addr_o_delay :
                              (op2_broadcast == 2'd1)? op2_weight_addr_o_delay :
                              (op3_broadcast == 2'd1)? op3_weight_addr_o_delay : 0;
    assign broadcast_data_i = (op0_broadcast == 2'd1)? op0_weight_sram_data_o :
                              (op0_broadcast == 2'd2)? op0_data_sram_data_o :
                              (op1_broadcast == 2'd1)? op1_weight_sram_data_o :
                              (op2_broadcast == 2'd1)? op2_weight_sram_data_o :
                              (op3_broadcast == 2'd1)? op3_weight_sram_data_o : 0;
    assign broadcast_number_of_elements_i = (op0_broadcast == 2'd1)? op0_weight_total_counts :
                                            (op0_broadcast == 2'd2)? op0_input_data_total_counts :
                                            (op1_broadcast == 2'd1)? op1_weight_total_counts :
                                            (op2_broadcast == 2'd1)? op2_weight_total_counts :
                                            (op3_broadcast == 2'd1)? op3_weight_total_counts : 0;
    // determine op0~3 data source, broadcast or not
    assign op0_data_sram_data_i = (op0_broadcast == 2'd2)? broadcast_data_o : op0_data_sram_data_o;
    assign op0_weight_sram_data_i = (op0_broadcast == 2'd1)? broadcast_data_o : op0_weight_sram_data_o;
    assign op1_weight_sram_data_i = (op1_broadcast == 2'd1)? broadcast_data_o : op1_weight_sram_data_o;
    assign op2_weight_sram_data_i = (op2_broadcast == 2'd1)? broadcast_data_o : op2_weight_sram_data_o;
    assign op3_weight_sram_data_i = (op3_broadcast == 2'd1)? broadcast_data_o : op3_weight_sram_data_o;
    
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            op0_data_sram_data_i_reg <= 0;
            op0_weight_sram_data_i_reg <= 0;
            op1_weight_sram_data_i_reg <= 0;
            op2_weight_sram_data_i_reg <= 0;
            op3_weight_sram_data_i_reg <= 0;
        end else begin
            op0_data_sram_data_i_reg <= op0_data_sram_data_i;
            op0_weight_sram_data_i_reg <= op0_weight_sram_data_i;
            op1_weight_sram_data_i_reg <= op1_weight_sram_data_i;
            op2_weight_sram_data_i_reg <= op2_weight_sram_data_i;
            op3_weight_sram_data_i_reg <= op3_weight_sram_data_i;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            op0_data_sram_en_delay <= 1'b0;
            op1_data_sram_en_delay <= 1'b0;
            op2_data_sram_en_delay <= 1'b0;
            op3_data_sram_en_delay <= 1'b0;
        end else begin
            op0_data_sram_en_delay <= op0_data_sram_en;
            op1_data_sram_en_delay <= op1_data_sram_en;
            op2_data_sram_en_delay <= op2_data_sram_en;
            op3_data_sram_en_delay <= op3_data_sram_en;
        end
    end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            op0_weight_addr_o_delay <= 0;
            op1_weight_addr_o_delay <= 0;
            op2_weight_addr_o_delay <= 0;
            op3_weight_addr_o_delay <= 0;
        end else begin
            op0_weight_addr_o_delay <= op0_weight_addr_o;
            op1_weight_addr_o_delay <= op1_weight_addr_o;
            op2_weight_addr_o_delay <= op2_weight_addr_o;
            op3_weight_addr_o_delay <= op3_weight_addr_o;
        end
    end

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
                if(op_total_data_counts >= expected_total_data_counts)
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

    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn)begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            layer_calc_done <= 1'b0;
        end else if(state == OP_DONE)begin
            layer_calc_done <= 1'b1;
        end else begin
            layer_calc_done <= 1'b0;
        end
    end


    op_decoder op_decoder_inst
    (
        .clk(s00_axis_aclk),
        .op(op),
        .valid_in(state==WAIT_OP),
        .rst(s00_axis_aresetn),
        .init(state == OP_DONE),
        .num_groups(groups),
        // Conv 
        .conv_valid_out(conv_valid_out),
        .conv_data_out(conv_data_out),
        .conv_data_in(conv_data_in),
        .conv_en(conv_en),
        // Fc
        .fc_valid_out(fc_valid_out),
        .fc_data_out(fc_data_out),
        .fc_data_in(fc_data_in),
        .fc_en(fc_en),
        // Exp
        .exp_valid_out(exp_valid_out),
        .exp_data_out(exp_data_out),
        .exp_data_in(exp_data_in),
        .exp_en(exp_en),
        // Reciprocal
        .reciprocal_valid_out(reciprocal_valid_out),
        .reciprocal_data_out(reciprocal_data_out),
        .reciprocal_data_in(reciprocal_data_in),
        .reciprocal_en(reciprocal_en),
        // Add
        .add_valid_out(add_valid_out),
        .add_data_out(add_data_out),
        .add_data_in(add_data_in),
        .add_weight_in(add_weight_i),
        .add_en(add_en),
        // Sub
        .sub_valid_out(sub_valid_out),
        .sub_data_out(sub_data_out),
        .sub_data_in(sub_data_in),
        .sub_weight_in(sub_weight_i),
        .sub_en(sub_en),
        // Mul
        .mul_valid_out(mul_valid_out),
        .mul_data_out(mul_data_out),
        .mul_data_in(mul_data_in),
        .mul_weight_in(mul_weight_i),
        .mul_en(mul_en),
        // signals for sram
        .store_to_sram_en(store_to_sram_en),
        .store_to_sram_data(store_to_sram_data),
        // op start signals and addrss
        .op0_data_sram_en(op0_data_sram_en),
        .op1_data_sram_en(op1_data_sram_en),
        .op2_data_sram_en(op2_data_sram_en),
        .op3_data_sram_en(op3_data_sram_en),
        .op0_data_addr_o(op0_data_addr_o),
        .op0_weight_addr_o(op0_weight_addr_o),
        .op1_weight_addr_o(op1_weight_addr_o),
        .op2_weight_addr_o(op2_weight_addr_o),
        .op3_weight_addr_o(op3_weight_addr_o),
        .op0_data_sram_data_i(op0_data_sram_data_i_reg),
        .op0_weight_sram_data_i(op0_weight_sram_data_i_reg),
        .op1_weight_sram_data_i(op1_weight_sram_data_i_reg),
        .op2_weight_sram_data_i(op2_weight_sram_data_i_reg),
        .op3_weight_sram_data_i(op3_weight_sram_data_i_reg),
        .op0_data_counts(op0_data_counts),
        .op1_data_counts(op1_data_counts),
        .op2_data_counts(op2_data_counts),
        .op3_data_counts(op3_data_counts),
        .op_total_data_counts(op_total_data_counts),
        .expected_total_data_counts(expected_total_data_counts)
    );

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
        .convolution_en(conv_en),
        .fc_en(fc_en),
        .conv_valid_o(conv_valid_out),
        .fc_valid_o(fc_valid_out),
        .conv_data_o(conv_data_out),
        .fc_data_o(fc_data_out),
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
        .output_offset(gemm_output_offset),
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
        .init(state == OP_DONE),
        .write_enable(write_enable),
        .write_address(write_address),
        .write_data(write_data),
        .data_type(data_type),
        .data_ready(data_ready),
        // WAIT_META  state signals
        .metadata_valid_i(metadata_valid_i),
        .op0_weight_sram_idx0(op0_weight_sram_idx0),
        .op0_weight_sram_idx1(op0_weight_sram_idx1),
        .op1_weight_sram_idx0(op1_weight_sram_idx0),
        .op2_weight_sram_idx0(op2_weight_sram_idx0),
        .op3_weight_sram_idx0(op3_weight_sram_idx0),
        .weight_num(weight_num),
        .weight_num_reg_o(weight_num_reg),
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
        .out_size(expected_total_data_counts),
        .groups(4'd8) //FIX: groups, 應該是要8 or groups? 
    );

    sram_controller #(.C_AXIS_TDATA_WIDTH(C_AXIS_TDATA_WIDTH)) sram_controller_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .mem_cal_en(state == WAIT_OP),
        // GEMM1 port, usually for data, op0_weight_idx1
        .gemm1_addr(gemm1_addr_i),
        .gemm1_data_in(),
        .gemm1_en(conv_en || fc_en),
        .gemm1_we(1'b0),
        .gemm1_idx(op0_weight_sram_idx1),
        .gemm1_data_out(gemm0_data_out),
        // GEMM2 port, usually for weight, op0_weight_idx0
        .gemm2_addr(weight_idx),
        .gemm2_data_in(),
        .gemm2_en(conv_en || fc_en),
        .gemm2_we(1'b0),
        .gemm2_idx(op0_weight_sram_idx0),
        .gemm2_data_out(gemm1_data_out),
        // ELEM port
        .elem_addr(idx1_out),
        .elem_data_in(),
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
        .sram_out_en(state == WRITE_OUTPUT),
        .sram_out_idx(store_sram_idx0),
        .sram_out_addr(sram_out_addr),
        .sram_out_data(sram_data_out),
        // op0 weight access sram
        .op0_weight_sram_en(op0_data_sram_en),
        .op0_weight_sram_addr_i(op0_weight_addr_o),
        .op0_weight_sram_idx(op0_weight_sram_idx0),
        .op0_weight_sram_data_o(op0_weight_sram_data_o),
        // op0 data access sram
        .op0_data_sram_en(op0_data_sram_en),
        .op0_data_sram_addr_i(op0_data_addr_o),
        .op0_data_sram_idx(op0_weight_sram_idx1),
        .op0_data_sram_data_o(op0_data_sram_data_o),
        // op1 weight access sram
        .op1_data_sram_en(op1_data_sram_en),
        .op1_data_sram_addr_i(op1_weight_addr_o),
        .op1_data_sram_idx(op1_weight_sram_idx0),
        .op1_data_sram_data_o(op1_weight_sram_data_o),
        // op2 weight access sram
        .op2_data_sram_en(op2_data_sram_en),
        .op2_data_sram_addr_i(op2_weight_addr_o),
        .op2_data_sram_idx(op2_weight_sram_idx0),
        .op2_data_sram_data_o(op2_weight_sram_data_o),
        // op3 weight access sram
        .op3_data_sram_en(op3_data_sram_en),
        .op3_data_sram_addr_i(op3_weight_addr_o),
        .op3_data_sram_idx(op3_weight_sram_idx0),
        .op3_data_sram_data_o(op3_weight_sram_data_o),
        // store op result to sram
        .result_sram_en(repacker_valid_out),
        .result_sram_we(repacker_valid_out),
        .result_sram_addr_i(repaker_output_index),
        .result_sram_data_i(repacker_data_out),
        .result_sram_idx(store_sram_idx0),
        // total memoory access counts
        .total_mem_access_counts(total_mem_access_counts),
        .store_access_sram_counts(store_access_sram_counts)
    );

    broadcast_unit broadcast_unit_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .init(state == OP_DONE),
        .valid_i(broadcast_valid_i),
        .en(broadcast_en),
        .data_i(broadcast_data_i),
        .addr_i(broadcast_addr_i),
        .number_of_elements_i(broadcast_number_of_elements_i),
        .valid_o(broadcast_valid_o),
        .data_o(broadcast_data_o)
    );

    element_wise element_wise_inst
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .init(state == OP_DONE),
        // exp port

        .groups(groups),
        .valid_in(requant_valid_o),
        .exp_deq_input_range_radius(exp_deq_input_range_radius),
        .exp_deq_input_zero_point(exp_deq_input_zero_point),
        .exp_deq_input_left_shift(exp_deq_input_left_shift),
        .exp_deq_input_multiplier(exp_deq_input_multiplier),
        .exp_req_input_quantized_multiplier(exp_req_input_quantized_multiplier),
        .exp_req_input_shift(exp_req_input_shift),
        .exp_req_input_offset(exp_req_input_offset),
        
        .data_out(exp_data_o),
        .valid_out(exp_valid_o),
        // -------------------------------------
        // Reciprocals port
        // -------------------------------------
        .reciprocal_deq_input_zero_point(reciprocal_deq_input_zero_point),
        .reciprocal_deq_input_range_radius(reciprocal_deq_input_range_radius),
        .reciprocal_deq_input_left_shift(reciprocal_deq_input_left_shift),
        .reciprocal_deq_input_multiplier(reciprocal_deq_input_multiplier),
        .reciprocal_req_input_quantized_multiplier(reciprocal_req_input_quantized_multiplier),
        .reciprocal_req_input_shift(reciprocal_req_input_shift),
        .reciprocal_req_input_offset(reciprocal_req_input_offset),
        // -------------------------------------
        // ADD metadata signals
        // -------------------------------------
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
        // -------------------------------------
        // SUB metadata signals
        // -------------------------------------
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
        // -------------------------------------
        // MUL metadata signals
        // -------------------------------------
        .mul_input1_offset(mul_input1_offset),
        .mul_input2_offset(mul_input2_offset),
        .mul_output_multiplier(mul_output_multiplier),
        .mul_output_shift(mul_output_shift),
        .mul_output_offset(mul_output_offset),
        .mul_quantized_activation_min(mul_quantized_activation_min),
        .mul_quantized_activation_max(mul_quantized_activation_max),
        // exp signals
        .exp_en(exp_en),
        .exp_data_in(exp_data_in),
        .exp_data_out(exp_data_out),
        .exp_valid_out(exp_valid_out),
        // reciprocal signals
        .reciprocal_en(reciprocal_en),
        .reciprocal_data_in(reciprocal_data_in),
        .reciprocal_data_out(reciprocal_data_out),
        .reciprocal_valid_out(reciprocal_valid_out),
        // add signals
        .add_en(add_en),
        .add_data_in(add_data_in),
        .add_data_out(add_data_out),
        .add_valid_out(add_valid_out),
        .add_weight_data_in(add_weight_i),
        // sub signals
        .sub_en(sub_en),
        .sub_data_in(sub_data_in),
        .sub_data_out(sub_data_out),
        .sub_valid_out(sub_valid_out),
        .sub_weight_data_in(sub_weight_i),
        // mul signals
        .mul_en(mul_en),
        .mul_data_in(mul_data_in),
        .mul_data_out(mul_data_out),
        .mul_valid_out(mul_valid_out),
        .mul_weight_data_in(mul_weight_i),
        .idx1_out(idx1_out)
    );
    wire [7:0] valid_mask;
    wire repacker_last;
    assign valid_mask = (1 << groups) - 1;
    assign repacker_last = (op_total_data_counts >= expected_total_data_counts);
    repacker #
    (
        .OUTPUT_WIDTH(C_AXIS_MDATA_WIDTH),
        .TOTAL_BTYES(8),
        .ACCU_WIDTH(2*C_AXIS_MDATA_WIDTH)
    ) repacker_inst 
    (
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .in_valid(store_to_sram_en),
        .data_i(store_to_sram_data),
        .valid_mask(valid_mask),
        .tlast_i(repacker_last),
        .out_valid(repacker_valid_out),
        .data_o(repacker_data_out)
    );

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            repaker_output_index <= 0;
        end else if(repacker_valid_out)begin
            repaker_output_index <= repaker_output_index + 1;
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

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            dram_access_counts <= 0;
        end else if(state == WRITE_OUTPUT || write_enable) begin
            dram_access_counts <= dram_access_counts + 1;
        end
    end 

    // DEBUG INFO
    // always @(posedge s00_axis_aclk)begin
    //     // if(exp_valid_o)begin
    //     //     $display("exp_data_o: %d, idx1_out: %d, out_size = %d, out_row = %d, out_col = %d, out_channel = %d, img_row = %d, img_col = %d, stride_h = %d, stride_w = %d, stored_num_groups_o = %d, conv_row = %d, conv_col = %d", exp_data_o,idx1_out,out_size,out_row,out_col,out_channel,img_row,img_col,stride_h,stride_w,stored_num_groups_o,conv_row,conv_col);
    //     // end
    //     // $display("state = %d",state);
    //     if(state == WAIT_OP) $display("op_total_data_counts = %d, expected_total = %d, groups = %d",op_total_data_counts, expected_total_data_counts,groups);
    //     // if(state == WAIT_META) $display("wait_meta, metadata_done = %d, weight_num_reg = %d",metadata_done,weight_num_reg);
    // end

    always @(posedge s00_axis_aclk) begin
        if(!s00_axis_aresetn) begin
            elementwise_idle_counts <= 0;
        end else if((!exp_en && !reciprocal_en && !add_en && !sub_en && !mul_en) && state == WAIT_OP) begin
            elementwise_idle_counts <= elementwise_idle_counts + 1;
        end
    end
endmodule
