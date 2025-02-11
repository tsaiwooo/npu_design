`timescale 1ns / 1ps

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
    input  wire [2*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s_axis_tuser,

    // SRAM control interface
    output reg                    write_enable,
    output reg [MAX_ADDR_WIDTH-1:0]   write_address,
    output reg signed [DATA_WIDTH-1:0] write_data,
    output reg [2:0]              data_type,      // 0: Image, 1: Kernel
    output reg                    data_ready,
    output reg [ADDR_WIDTH-1:0]   img_row,
    output reg [ADDR_WIDTH-1:0]   img_col,
    output reg [ADDR_WIDTH-1:0]   ker_row,
    output reg [ADDR_WIDTH-1:0]   ker_col,
    output reg [NUM_CHANNELS_WIDTH-1:0] num_channels
);

    // FSM states   
    localparam ST_IDLE = 0;
    localparam ST_IMG  = 1;
    localparam ST_KER  = 2;

    reg [1:0] state, next_state;
    reg [MAX_ADDR_WIDTH-1:0] address_counter;

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
                if (s_axis_tvalid)
                    next_state = ST_IMG;
                else
                    next_state = ST_IDLE;
            end
            ST_IMG: begin
                if (s_axis_tlast)
                    next_state = ST_KER;
                else
                    next_state = ST_IMG;
            end
            ST_KER: begin
                if (s_axis_tlast)
                    next_state = ST_IDLE;
                else
                    next_state = ST_KER;
            end
            default: next_state = ST_IDLE;
        endcase
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
            if (state == ST_IMG)
                data_type <= GEMM0_SRAM_IDX;
            else if (state == ST_KER)
                data_type <= GEMM1_SRAM_IDX;
            else
                data_type <= data_type; // keep unchanged
        end else
            data_type <= data_type; // keep unchanged
    end

    // img_row
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            img_row <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            if (state == ST_IMG)
                img_row <= s_axis_tuser[2*ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : ADDR_WIDTH + NUM_CHANNELS_WIDTH];
            else
                img_row <= img_row; // keep unchanged
        end else
            img_row <= img_row; // keep unchanged
    end

    // img_col
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            img_col <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            if (state == ST_IMG)
                img_col <= s_axis_tuser[ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : NUM_CHANNELS_WIDTH];
            else
                img_col <= img_col; // keep unchanged
        end else
            img_col <= img_col; // keep unchanged
    end

    // ker_row
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            ker_row <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            if (state == ST_KER)
                ker_row <= s_axis_tuser[2*ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : ADDR_WIDTH + NUM_CHANNELS_WIDTH];
            else
                ker_row <= ker_row; // keep unchanged
        end else
            ker_row <= ker_row; // keep unchanged
    end

    // ker_col
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            ker_col <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            if (state == ST_KER)
                ker_col <= s_axis_tuser[ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : NUM_CHANNELS_WIDTH];
            else
                ker_col <= ker_col; // keep unchanged
        end else
            ker_col <= ker_col; // keep unchanged
    end

    // num_channels
    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn)
            num_channels <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            num_channels <= s_axis_tuser[NUM_CHANNELS_WIDTH -1 : 0];
        end else
            num_channels <= num_channels; // keep unchanged
    end

endmodule
