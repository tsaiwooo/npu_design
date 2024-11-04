`timescale 1ns / 1ps
`include "params.vh"

module convolution #
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8
)
(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   en,
    // input metadata
    input  wire [ADDR_WIDTH-1:0]  img_row,
    input  wire [ADDR_WIDTH-1:0]  img_col,
    input  wire [ADDR_WIDTH-1:0]  ker_row,
    input  wire [ADDR_WIDTH-1:0]  ker_col,
    // img and kernel data
    input  wire [SRAM_WIDTH_O-1:0]  data_in,
    input  wire [SRAM_WIDTH_O-1:0]  weight_in,
    // output signal control
    output wire                   mac_valid_out,
    output wire signed [2*DATA_WIDTH-1:0] mac_out,
    // output image metadata
    output reg [ADDR_WIDTH-1:0]  conv_row,
    output reg [ADDR_WIDTH-1:0]  conv_col,
    output reg [ADDR_WIDTH-1:0]  for_conv_row,
    output reg [ADDR_WIDTH-1:0]  for_conv_col,
    // output weight idx metadata
    output [ADDR_WIDTH-1:0]  weight_idx_o,
    output reg [ADDR_WIDTH-1:0]  idx1_out
);
    reg en_delay;
    
    reg [ADDR_WIDTH-1:0] for_conv_row_delay;
    reg [ADDR_WIDTH-1:0] for_conv_col_delay;

    wire [6:0] shift_amount;
    wire [6:0] nums_input;
    assign shift_amount = $clog2(DATA_WIDTH);
    assign nums_input = SRAM_WIDTH_O >> shift_amount;

    reg [$clog2(MAX_MACS):0] data_count;
    wire [$clog2(MAX_MACS):0] total_macs;
    reg [DATA_WIDTH * MAX_MACS - 1 : 0] data_mac_i;
    reg [DATA_WIDTH * MAX_MACS - 1 : 0] weight_mac_i;

    assign total_macs = ker_row * ker_col;
    reg mac_valid_in;

    wire [ADDR_WIDTH-1:0] out_row;
    wire [ADDR_WIDTH-1:0] out_col;
    assign out_row = img_row - ker_row + 1;
    assign out_col = img_col - ker_col + 1;

    // control output weight idx
    reg [ADDR_WIDTH-1:0] weight_idx;
    reg [ADDR_WIDTH-1:0] weight_idx_delay;
    assign weight_idx_o = weight_idx;

    always @(posedge clk) begin
        en_delay <= en;
    end

    // control convolution index
    always @(posedge clk) begin
        if (!rst) begin
            conv_col <= 0;
        end else if(conv_col == out_col - 1 && conv_row == out_row - 1  && mac_valid_in) begin
            conv_col <= 0;
        end else if (mac_valid_in) begin
            if (conv_col < out_col -1) begin
                conv_col <= conv_col + 1;  // Hold current value
            end else begin
                conv_col <= 0;
            end
        end 
    end

    // conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            conv_row <= 0;
        end else if(conv_col == out_col - 1 && conv_row == out_row - 1 && mac_valid_in) begin
            conv_row <= 0; 
        end else if (mac_valid_in) begin
            if (conv_col < out_col - 1) begin
                conv_row <= conv_row;  // Hold current value
            end else begin
                conv_row <= conv_row + 1;
            end
        end 
    end

    // for_conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_row <= 0;
        end else if (en) begin
            if ( for_conv_col + nums_input >= ker_col ) begin
                for_conv_row <= for_conv_row + 1;
            end else begin
                for_conv_row <= for_conv_row;
            end
        end else begin
            for_conv_row <= 0;
        end
    end

    // for_conv_col Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_col <= 0;
        end else if (en) begin
            if (for_conv_col + nums_input < ker_col) begin
                for_conv_col <= for_conv_col + nums_input;
            end else begin
                for_conv_col <= 0;
            end
        end else begin
            for_conv_col <= 0;
        end
    end

    always @(posedge clk)begin
        for_conv_row_delay <= for_conv_row;
    end

    always @(posedge clk)begin
        for_conv_col_delay <= for_conv_col;
    end

    // control mac_valid_in
    always @(posedge clk) begin
        if (!rst) begin
            mac_valid_in <= 1'b0;
        end else if (en_delay && for_conv_row == ker_row  ) begin
            mac_valid_in <= 1'b1;
        end else begin
            mac_valid_in <= 1'b0;
        end
    end



    // control data_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            data_mac_i <= 0;
        end else if (en_delay) begin
            integer idx;
            // idx = for_conv_row * ker_col + for_conv_col;
            // 1. idx每次要取的數量要小於nums_input, 2. 以及不能超過ker_col, 3. 還有要判斷是否超過total_macs
            for(idx = 0; idx < ker_col && idx < nums_input &&  (idx + for_conv_col_delay + for_conv_row_delay * ker_col) < total_macs; idx = idx + 1)begin
                data_mac_i[(idx + for_conv_row_delay * ker_col + for_conv_col) * DATA_WIDTH +: DATA_WIDTH] <= data_in[idx * DATA_WIDTH +: DATA_WIDTH];
            end
            // if (idx && idx <= total_macs) begin
            //     data_mac_i[(idx-1) * DATA_WIDTH +: DATA_WIDTH] <= data_in;
            // end
        end
    end


    always @(posedge clk) begin
        if (!rst) begin
            weight_idx <= 0;
        end else if (en) begin
            if (weight_idx < total_macs) begin
                weight_idx <= weight_idx + nums_input;
            end else begin
                weight_idx <= weight_idx;
            end
        end else begin
            weight_idx <= 0;
        end
    end

    always @(posedge clk)begin
        weight_idx_delay <= weight_idx;
    end


    // control weight_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            weight_mac_i <= 0;
        end else if (en_delay) begin
            integer idx;
            // idx = for_conv_row * ker_col + for_conv_col;
            for(idx = 0;  idx < nums_input && idx + weight_idx_delay < total_macs ; idx = idx + 1)begin
                weight_mac_i[(weight_idx_delay + idx) * DATA_WIDTH +: DATA_WIDTH] <= weight_in[idx * DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end

    // control data_count
    always @(posedge clk) begin
        if (!rst || !en) begin
            data_count <= 0;
        end else if (en) begin
            integer idx;
            idx = for_conv_row * ker_col + for_conv_col;
            if (idx && idx <= total_macs) begin
                data_count <= data_count + 1;
            end
        end
    end

    // control output index
    always @(posedge clk) begin
        if (!rst) begin
            idx1_out <= 0;
        end else if (mac_valid_out) begin
            idx1_out <= idx1_out + 1;
        end
    end


    mac #
    (
        .MAX_MACS(MAX_MACS),
        .DATA_WIDTH(DATA_WIDTH)
    )
    mac_gen (
        .clk(clk),
        .rst(rst),
        .num_macs_i(total_macs),
        .valid_in(mac_valid_in),
        .data(data_mac_i),
        .weight(weight_mac_i),
        .mac_out(mac_out),
        .valid_out(mac_valid_out)
    );

endmodule