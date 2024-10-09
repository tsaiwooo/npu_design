`timescale 1ns / 1ps

module sram_dp
#(
    parameter DATA_WIDTH = 8,
    parameter N_ENTRIES = 4096,
    parameter ADDRW = $clog2(N_ENTRIES),
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1)
)
(
    input                         clk1_i,
    input                         en1_i,
    input                         we1_i,
    input  [NUM_CHANNELS_WIDTH-1:0] num_channels1_i,
    input  [ADDRW*MAX_CHANNELS-1 : 0]          addr1_i,
    input  [DATA_WIDTH*MAX_CHANNELS-1 : 0]     data1_i,
    output reg [DATA_WIDTH*MAX_CHANNELS-1 : 0] data1_o,
    output reg                    ready1_o,

    input                         clk2_i,
    input                         en2_i,
    input                         we2_i,
    input  [NUM_CHANNELS_WIDTH-1:0] num_channels2_i,
    input  [ADDRW*MAX_CHANNELS-1 : 0]          addr2_i,
    input  [DATA_WIDTH*MAX_CHANNELS-1 : 0]     data2_i,
    output reg [DATA_WIDTH*MAX_CHANNELS-1 : 0] data2_o,
    output reg                    ready2_o
);

    reg [DATA_WIDTH-1 : 0] RAM [N_ENTRIES-1 : 0];

    // ------------------------------------
    // port1 read
    // ------------------------------------
    always @(posedge clk1_i) begin
        integer i;
        if (en1_i) begin
            for (i = 0; i < num_channels1_i; i = i + 1) begin
                data1_o[DATA_WIDTH*(i+1)-1 -: DATA_WIDTH] <= RAM[addr1_i[ADDRW*(i+1)-1 -: ADDRW]];
            end
            ready1_o <= 1;
        end else begin
            ready1_o <= 0;
        end
    end

    // ------------------------------------
    // port write
    // ------------------------------------
    always @(posedge clk1_i) begin
        integer i;
        if (en1_i & we1_i) begin
            for (i = 0; i < num_channels1_i; i = i + 1) begin
                RAM[addr1_i[ADDRW*(i+1)-1 -: ADDRW]] <= data1_i[DATA_WIDTH*(i+1)-1 -: DATA_WIDTH];
            end
        end
    end

    // ------------------------------------
    // port2 read
    // ------------------------------------
    always @(posedge clk2_i) begin
        integer i;
        if (en2_i) begin
            for (i = 0; i < num_channels2_i; i = i + 1) begin
                data2_o[DATA_WIDTH*(i+1)-1 -: DATA_WIDTH] <= RAM[addr2_i[ADDRW*(i+1)-1 -: ADDRW]];
            end
            ready2_o <= 1;
        end else begin
            ready2_o <= 0;
        end
    end

    // ------------------------------------
    // port2 write
    // ------------------------------------
    always @(posedge clk2_i) begin
        integer i;
        if (en2_i & we2_i) begin
            for (i = 0; i < num_channels2_i; i = i + 1) begin
                RAM[addr2_i[ADDRW*(i+1)-1 -: ADDRW]] <= data2_i[DATA_WIDTH*(i+1)-1 -: DATA_WIDTH];
            end
        end
    end

endmodule   // sram_dp
