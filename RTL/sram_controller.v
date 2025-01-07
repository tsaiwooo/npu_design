`timescale 1ns / 1ps
`include "params.vh"

module sram_controller# ( parameter C_AXIS_TDATA_WIDTH = 8 )
(
    input clk,
    input rst,

    // GEMM1 port
    input [MAX_ADDR_WIDTH-1:0] gemm1_addr,
    input [C_AXIS_TDATA_WIDTH-1:0] gemm1_data_in,
    input  gemm1_en,
    input  gemm1_we,
    input [NUM_SRAMS-1:0] gemm1_idx,
    output signed [SRAM_WIDTH_O-1:0] gemm1_data_out,

    // GEMM2 port
    input [MAX_ADDR_WIDTH-1:0] gemm2_addr,
    input [C_AXIS_TDATA_WIDTH-1:0] gemm2_data_in,
    input  gemm2_en,
    input  gemm2_we,
    input [NUM_SRAMS-1:0] gemm2_idx,
    output signed [SRAM_WIDTH_O-1:0] gemm2_data_out,
    
    // ELEM port
    input [MAX_ADDR_WIDTH-1:0] elem_addr,
    input signed [4*C_AXIS_TDATA_WIDTH-1:0] elem_data_in,
    input  elem_en,
    input  elem_we,
    input [NUM_SRAMS-1:0] elem_idx,
    output signed [SRAM_WIDTH_O-1:0] elem_data_out,

    // axi4 input port
    input [MAX_ADDR_WIDTH-1:0] write_address,
    input [C_AXIS_TDATA_WIDTH-1:0] write_data,
    input [2:0] axi_idx,
    input write_enable,

    // axi4 output port
    input sram_out_en,
    input [NUM_SRAMS-1:0] sram_out_idx,
    input [MAX_ADDR_WIDTH-1:0] sram_out_addr,
    output signed [SRAM_WIDTH_O-1:0] sram_out_data
);
    reg [NUM_SRAMS-1:0] en;
    reg [NUM_SRAMS-1:0] we;
    reg [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr;
    reg [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_in;
    wire [NUM_SRAMS * SRAM_WIDTH_O - 1 : 0] data_out;
    reg signed [SRAM_WIDTH_O-1:0] each_data_out[NUM_SRAMS];

    assign gemm1_data_out = each_data_out[gemm1_idx];
    assign gemm2_data_out = each_data_out[gemm2_idx];
    assign elem_data_out = each_data_out[elem_idx];
    assign sram_out_data = each_data_out[sram_out_idx];

    integer i;
    always @(*)begin
        for(i = 0; i < NUM_SRAMS; i = i + 1)begin
            each_data_out[i] = data_out[i * SRAM_WIDTH_O +: SRAM_WIDTH_O];
        end
    end

    always @(*)begin
        we = {NUM_SRAMS{1'b0}};
        if(gemm1_we)begin
            we[gemm1_idx] = 1'b1;
        end
        if(gemm2_we)begin
            we[gemm2_idx] = 1'b1;
        end
        if(elem_we)begin
            we[elem_idx] = 1'b1;
            if(elem_addr < 4'd10)
                $display("Writing mac data to SRAM, address = %d, data = %d", elem_addr, elem_data_in);
        end
        if(write_enable)begin
            we[axi_idx] = 1'b1;
        end
    end

    always @(*)begin
        en = {NUM_SRAMS{1'b0}};
        if(gemm1_en)begin
            en[gemm1_idx] = 1'b1;
        end
        if(gemm2_en)begin
            en[gemm2_idx] = 1'b1;
        end
        if(elem_en)begin
            en[elem_idx] = 1'b1;
        end
        if(sram_out_en)begin
            en[sram_out_idx] = 1'b1;
        end
        if(write_enable)begin
            en[axi_idx] = 1'b1;
        end

    end

    always @(*)begin
        addr = {NUM_SRAMS * MAX_ADDR_WIDTH{1'b0}};
        if(gemm1_en)begin
            addr[gemm1_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = gemm1_addr;
        end
        if(gemm2_en)begin
            addr[gemm2_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = gemm2_addr;
        end
        if(elem_en)begin
            addr[elem_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = elem_addr;
        end
        if(sram_out_en)begin
            addr[sram_out_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = sram_out_addr;
        end
        if(write_enable)begin
            addr[axi_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = write_address;
        end
    end

    always @(*)begin
        data_in = {NUM_SRAMS * MAX_DATA_WIDTH{1'b0}};
        if(write_enable)begin
            data_in[axi_idx * MAX_DATA_WIDTH +: C_AXIS_TDATA_WIDTH] = write_data;
        end
        if(gemm1_we)begin
            data_in[gemm1_idx * MAX_DATA_WIDTH +: MAX_DATA_WIDTH] = gemm1_data_in;
        end
        if(gemm2_we)begin
            data_in[gemm2_idx * MAX_DATA_WIDTH +: MAX_DATA_WIDTH] = gemm2_data_in;
        end
        if(elem_we)begin
            data_in[elem_idx * MAX_DATA_WIDTH +: MAX_DATA_WIDTH] = elem_data_in;
        end
    end
    
    // control SRAM
    multi_sram  multi_sram_gen (
        .clk(clk),
        .rst(rst),
        .en(en),
        .we(we),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

endmodule