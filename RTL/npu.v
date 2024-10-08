`timescale 1ns / 1ps

module NPU#
(
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 8,
    parameter C_AXIS_MDATA_WIDTH = 8
)
(
    /* AXI slave interface (input to the FIFO) */
    input  wire                   s00_axis_aclk,
    input  wire                   s00_axis_aresetn,
    input  wire [C_AXIS_TDATA_WIDTH-1:0]  s00_axis_tdata,
    input  wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tstrb,
    input  wire                   s00_axis_tvalid,
    output wire                   s00_axis_tready,
    input  wire                   s00_axis_tlast,
    
    /* * AXI master interface (output of the FIFO) */
    input  wire                   m00_axis_aclk,
    input  wire                   m00_axis_aresetn,
    output wire [C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output wire [(C_AXIS_MDATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
    output wire                   m00_axis_tvalid,
    input  wire                   m00_axis_tready,
    output wire                   m00_axis_tlast
);


    // State definitions using localparam
    localparam IDLE         = 3'd0;
    localparam LOAD         = 3'd1;
    localparam COMPUTE_CONV = 3'd2;
    localparam ACTIVATION   = 3'd3;
    localparam WRITE_OUTPUT = 3'd4;

    reg [2:0] state;  // Current state of the FSM

    /**** control input data signals ****/
    // port1 signals
    wire en1_i,we1_i,ready1_o;
    reg [ADDR_WIDTH-1:0] idx1;
    wire [ADDR_WIDTH-1:0] data1_o;
    // port1 for input write sram
    assign s00_axis_tready = s00_axis_tvalid;
    assign we1_i = s00_axis_tvalid & s00_axis_tready;
    assign en1_i = (we1_1)? 1 : 0; // enable access sram 1 port, modify if if we have another data want to read from this port


    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn) begin
            idx1 <= 0;
        end else if(we1_i)begin
            idx1 <= idx1 + 1'b1;
        end
    end

    // port1 for input read data
    wire [ADDR_WIDTH-1:0] data_in;


    // port2 signals
    wire en2_i,we2_i,ready2_o;
    reg [ADDR_WIDTH-1:0] idx2;
    wire [ADDR_WIDTH-1:0] data2_o;
    wire [ADDR_WIDTH-1:0] data2_i;
    
    // port2 for input write sram
    
    // port2 for input read data
    assign we2_i = 0; // now, we do not need port2 wrire data
    assign en2_i = 
    /**** control input data signals ****/

    /* control output data signals */


    /* control output data signals */
    sram #
    (
        .DATA_WIDTH(C_AXIS_TDATA_WIDTH),
        .N_ENTRIES(2**ADDR_WIDTH - 1),
        .ADDRW(ADDR_WIDTH)
    )
    sram_i(
        .clk1_i(s00_axis_aclk),
        .en1_i(en1_i),
        .we1_i(we1_i),
        .addr1_i(idx1),
        .data1_i(s00_axis_tdata),
        .data1_o(data1_o),
        .ready1_o(ready1_o),
        .clk2_i(s00_axis_aclk),
        .we2_i(we2_i),
        .en2_i(en2_i),
        .addr2_i(addr2_i),
        .data2_i(data2_i),
        .data2_o(data2_o),
        .ready2_o(ready2_o)
    );

    sram #
    (
        .DATA_WIDTH(C_AXIS_MDATA_WIDTH),
        .N_ENTRIES(2**ADDR_WIDTH - 1),
        .ADDRW(ADDR_WIDTH)
    )
    sram_o(
        .clk_i(s00_axis_aclk),
        .en_i(in_en),
        .addr_i(),
        .data_i(),
        .data_o()
    );
    

endmodule
