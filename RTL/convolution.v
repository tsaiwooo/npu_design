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
    input  wire [DATA_WIDTH-1:0]  data_in,
    input  wire [DATA_WIDTH-1:0]  weight_in,
    // output signal control
    output wire                   mac_valid_out,
    output wire signed [2*DATA_WIDTH-1:0] mac_out,
    // output metadata
    output reg [ADDR_WIDTH-1:0]  conv_row,
    output reg [ADDR_WIDTH-1:0]  conv_col,
    output reg [ADDR_WIDTH-1:0]  for_conv_row,
    output reg [ADDR_WIDTH-1:0]  for_conv_col,
    output reg [ADDR_WIDTH-1:0]  idx1_out
);

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

    // control convolution index
    always @(posedge clk) begin
        if (!rst) begin
            conv_row <= 0;
        end else if (en) begin
            if (for_conv_row < ker_row - 1 || for_conv_col < ker_col - 1) begin
                conv_row <= conv_row;  // Hold current value
            end else if (for_conv_row == ker_row - 1 && for_conv_col == ker_col - 1) begin
                conv_row <= conv_row;  // Hold current value
            end else begin
                if (conv_col < out_col - 1) begin
                    conv_row <= conv_row;
                end else begin
                    if (conv_row < out_row - 1) begin
                        conv_row <= conv_row + 1;
                    end else begin
                        conv_row <= 0;
                    end
                end
            end
        end
    end

    // conv_col Logic
    always @(posedge clk) begin
        if (!rst) begin
            conv_col <= 0;
        end else if (en) begin
            if (for_conv_row < ker_row - 1 || for_conv_col < ker_col - 1) begin
                conv_col <= conv_col;  // Hold current value
            end else if (for_conv_row == ker_row - 1 && for_conv_col == ker_col - 1) begin
                conv_col <= conv_col;  // Hold current value
            end else begin
                if (conv_col < out_col - 1) begin
                    conv_col <= conv_col + 1;
                end else begin
                    conv_col <= 0;
                end
            end
        end
    end

    // for_conv_row Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_row <= 0;
        end else if (en) begin
            if (for_conv_row < ker_row - 1 || for_conv_col < ker_col - 1) begin
                if (for_conv_col < ker_col - 1) begin
                    for_conv_row <= for_conv_row;  // Hold current value
                end else if (for_conv_row < ker_row - 1) begin
                    for_conv_row <= for_conv_row + 1;
                end
            end else if (for_conv_row == ker_row - 1 && for_conv_col == ker_col - 1) begin
                for_conv_row <= for_conv_row;  // Hold current value
            end else begin
                for_conv_row <= 0;  // Reset when kernel traversal is complete
            end
        end
    end

    // for_conv_col Logic
    always @(posedge clk) begin
        if (!rst) begin
            for_conv_col <= 0;
        end else if (en) begin
            if (for_conv_row < ker_row - 1 || for_conv_col < ker_col - 1) begin
                if (for_conv_col < ker_col - 1) begin
                    for_conv_col <= for_conv_col + 1;
                end else begin
                    for_conv_col <= 0;
                end
            end else if (for_conv_row == ker_row - 1 && for_conv_col == ker_col - 1) begin
                for_conv_col <= for_conv_col + 1;
            end else begin
                for_conv_col <= 0;  // Reset after reaching kernel boundaries
            end
        end
    end

    // control mac_valid_in
    always @(posedge clk) begin
        if (!rst) begin
            mac_valid_in <= 1'b0;
        end else if (en && data_count == total_macs-1) begin
            mac_valid_in <= 1'b1;
        end else begin
            mac_valid_in <= 1'b0;
        end
    end



    // control data_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            data_mac_i <= 0;
        end else if (en) begin
            integer idx;
            idx = for_conv_row * ker_col + for_conv_col;
            if (idx && idx <= total_macs) begin
                data_mac_i[(idx-1) * DATA_WIDTH +: DATA_WIDTH] <= data_in;
            end
        end
    end

    // control weight_mac_i
    always @(posedge clk) begin
        if (!rst || !en) begin
            weight_mac_i <= 0;
        end else if (en) begin
            integer idx;
            idx = for_conv_row * ker_col + for_conv_col;
            if (idx && idx <= total_macs) begin
                weight_mac_i[(idx-1) * DATA_WIDTH +: DATA_WIDTH] <= weight_in;
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