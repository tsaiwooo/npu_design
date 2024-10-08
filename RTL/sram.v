`timescale 1ns / 1ps

module sram_dp
#(parameter DATA_WIDTH = 32, N_ENTRIES = 1024, ADDRW = $clog2(N_ENTRIES))
(
    input                         clk1_i,
    input                         en1_i,
    input                         we1_i,
    input  [ADDRW-1 : 0]          addr1_i,
    input  [DATA_WIDTH-1 : 0]     data1_i,
    output reg [DATA_WIDTH-1 : 0] data1_o,
    output reg                    ready1_o,

    input                         clk2_i,
    input                         en2_i,
    input                         we2_i,
    input  [ADDRW-1 : 0]          addr2_i,
    input  [DATA_WIDTH-1 : 0]     data2_i,
    output reg [DATA_WIDTH-1 : 0] data2_o,
    output reg                    ready2_o
);

reg [DATA_WIDTH-1 : 0] RAM [N_ENTRIES-1 : 0];

// ------------------------------------
// Read operation on port #1
// ------------------------------------
always@(posedge clk1_i)
begin
    if (en1_i)
    begin
        data1_o <= RAM[addr1_i];
        ready1_o <= 1;
    end
    else
        ready1_o <= 0;
end

// ------------------------------------
// Write operations on port #1
// ------------------------------------
always@(posedge clk1_i)
begin
    if (en1_i & we1_i)
    begin
        RAM[addr1_i] <= data1_i;
    end
end

// ------------------------------------
// Read operation on port #2
// ------------------------------------
always@(posedge clk2_i)
begin
    if (en2_i)
    begin
        data2_o <= RAM[addr2_i];
        ready2_o <= 1;
    end
    else
        ready2_o <= 0;
end

// ------------------------------------
// Write operations on port #2
// ------------------------------------
always@(posedge clk2_i)
begin
    if (en2_i & we2_i)
    begin
        RAM[addr2_i] <= data2_i;
    end
end

endmodule   // sram_dp