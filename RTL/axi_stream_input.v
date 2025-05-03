`timescale 1ns / 1ps
// send s_axis_tuser with the format of [batch, height, width, in_channel] in input_data
// send s_axis_tuser with the format of [out_channel, height, width, in_channel] in kernel_data
// send s_axis_tuser with the format of [stride_h, stride_w, padding] in first time when sending data
module axi_stream_input #
(
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8,
    parameter NUM_CHANNELS_WIDTH = $clog2(64+1)
)
(
    input  wire                   s_axis_aclk,
    input  wire                   s_axis_aresetn,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [(DATA_WIDTH/8)-1 : 0] s_axis_tstrb,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [4*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s_axis_tuser,
    // WAIT_META state signals
    input  wire                   metadata_valid_i,
    input  wire [2:0]             op0_weight_sram_idx0,
    input  wire [2:0]             op0_weight_sram_idx1,
    input  wire [2:0]             weight_num,
    output reg  [2:0]             weight_num_reg_o,
    // SRAM control interface
    output reg                    write_enable,
    output reg [MAX_ADDR_WIDTH-1:0]   write_address,
    output reg signed [DATA_WIDTH-1:0] write_data,
    output reg [2:0]              data_type,      // different op weight sram
    output reg                    data_ready,
    // output reg [ADDR_WIDTH-1:0]   batch,
    // output reg [ADDR_WIDTH-1:0]   img_row,
    // output reg [ADDR_WIDTH-1:0]   img_col,
    // output reg [ADDR_WIDTH-1:0]   in_channel,
    // output reg [ADDR_WIDTH-1:0]   ker_row,
    // output reg [ADDR_WIDTH-1:0]   ker_col,
    // output reg [ADDR_WIDTH-1:0]   output_channel,
    // output reg [3:0]              stride_h,
    // output reg [3:0]              stride_w,
    // output reg                    padding,
    output reg [NUM_CHANNELS_WIDTH-1:0] num_channels
);
    // reg [ADDR_WIDTH-1:0] batch,img_row,img_col,in_channel,ker_row,ker_col,output_channel;
    // reg [3:0] stride_h,stride_w;
    // reg padding;

    // FSM states   
    localparam ST_IDLE = 0;
    localparam ST_IMG  = 1;
    localparam ST_KER  = 2;

    reg [1:0] state, next_state;
    reg [MAX_ADDR_WIDTH-1:0] address_counter;
    reg metadata_read_done;

    assign s_axis_tready = s_axis_tvalid; // always ready for data

    // input for which sram
    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            ST_IDLE: begin
                if (s_axis_tvalid && weight_num > 0)
                    next_state = ST_IMG;
                else
                    next_state = ST_IDLE;
            end
            ST_IMG: begin
                if (s_axis_tlast && weight_num_reg_o == 0)
                    next_state = ST_IDLE;
                else
                    next_state = ST_IMG;
            end
            // ST_KER: begin
            //     if (s_axis_tlast)
            //         next_state = ST_IDLE;
            //     else
            //         next_state = ST_KER;
            // end
            default: next_state = ST_IDLE;
        endcase
    end

    // metadata_read_done
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            metadata_read_done <= 1'b0;
        else if (metadata_valid_i)
            metadata_read_done <= 1'b1;
        else if(weight_num_reg_o == 0)
            metadata_read_done <= 1'b0;
        else
            metadata_read_done <= metadata_read_done;
    end
    // store weight_num
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if(!s_axis_aresetn) 
            weight_num_reg_o <= 0;
        else if(s_axis_tlast) begin
            weight_num_reg_o <= weight_num_reg_o - 1;
            $display("weight_num_reg_o: %d", weight_num_reg_o);
        end else if (metadata_valid_i && !metadata_read_done) begin
            weight_num_reg_o <= weight_num;
            $display("reset weight, num = %d", weight_num);
        end else
            weight_num_reg_o <= weight_num_reg_o;
    end

    // write_enable
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            write_enable <= 1'b0;
        else if (s_axis_tvalid && s_axis_tready)
            write_enable <= 1'b1;
        else
            write_enable <= 1'b0;
    end

    // write_data
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            write_data <= 0;
        else if (s_axis_tvalid && s_axis_tready)
            write_data <= s_axis_tdata;
        else
            write_data <= write_data; // keep unchanged
    end

    // write_address
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            write_address <= 0;
        else if (s_axis_tvalid && s_axis_tready)
            write_address <= address_counter;
        else
            write_address <= write_address; // keep unchanged
    end

    // address_counter
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            address_counter <= 0;
        else if (s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tlast)
                address_counter <= 0;
            else
                address_counter <= address_counter + 1;
        end else
            address_counter <= address_counter; // keep unchanged
    end

    // data_ready
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            data_ready <= 1'b0;
        else if (s_axis_tvalid && s_axis_tready)
            data_ready <= 1'b1;
        else
            data_ready <= 1'b0;
    end

    // data_type
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            data_type <= 0;
        else if (s_axis_tvalid && s_axis_tready) begin
            case(weight_num_reg_o)
                1: data_type <= op0_weight_sram_idx1;
                2: data_type <= op0_weight_sram_idx0    ;
                default: data_type <= 0;
            endcase
            // if (state == ST_IMG)
            //     data_type <= op0_weight_sram_idx0;
            // else if (state == ST_KER)
            //     data_type <= op0_weight_sram_idx1;
            // else
            //     data_type <= data_type; // keep unchanged
        end else
            data_type <= data_type; // keep unchanged
    end
    

endmodule
