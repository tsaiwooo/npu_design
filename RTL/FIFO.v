// circular FIFO
// read zero-cycle latency

`timescale 1ns/1ps

module FIFO #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = 3
)
(
    input  wire                   clk,
    input  wire                   rst,      // Can be synchronous or asynchronous reset
    input  wire                   wr,       // Write enable
    input  wire                   rd,       // Read enable
    input  wire [DATA_WIDTH-1:0]  data_in,
    output reg  [DATA_WIDTH-1:0]  data_out,
    output wire                   full,     // This can be interpreted as a "full" flag
    output wire                   empty
);
     // -------------------------------------------------
    // [1] Internal memory (storage for FIFO)
    // -------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------
    // [2] Write/Read pointers
    // -------------------------------------------------
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    // -------------------------------------------------
    // [3] FIFO status (full / empty)
    // -------------------------------------------------
    // When wr_ptr_next == rd_ptr, the FIFO is considered full.
    // Note that wr_ptr_next is wr_ptr + 1, wrapped by the ADDR_WIDTH.
    wire [ADDR_WIDTH-1:0] wr_ptr_next = wr_ptr + 1'b1;
    assign full = (wr_ptr_next == rd_ptr);
    // assign full = full_i;

    assign empty = (wr_ptr == rd_ptr);

    // -------------------------------------------------
    // [4] Write logic
    // -------------------------------------------------
    // (a) Reset wr_ptr to zero when rst is active
    // (b) If wr && !full, then perform a write to memory
    always @(posedge clk) begin
        if (!rst) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
        end 
        else if (wr && !full) begin
            mem[wr_ptr] <= data_in;
            wr_ptr      <= wr_ptr_next;  // Advance write pointer
            $display($time, " [write_data] Write 0x%h to FIFO, wr_ptr = %d, rd_ptr = %d", data_in, wr_ptr, rd_ptr);
        end
    end

    //-----------------------------------------------------
    // [5] Read logic: zero-cycle latency
    //-----------------------------------------------------
    // We split the pointer update (sequential) and data_out assignment (combinational).
    // (a) Reset rd_ptr on rst
    // (b) If rd && !empty, increment rd_ptr
    // (c) data_out is driven combinationally from mem[rd_ptr].
    always @(posedge clk) begin
        if (!rst) begin
            rd_ptr <= {ADDR_WIDTH{1'b0}};
        end 
        else if (rd && !empty) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // Combinational read: as soon as rd is asserted (and not empty),
    // the memory output is driven to data_out in the same cycle.
    // If empty, we can choose to drive 0 or keep previous data, depending on design choice.
    assign data_out = (!empty) ? mem[rd_ptr] : {DATA_WIDTH{1'b0}};
    
    
endmodule