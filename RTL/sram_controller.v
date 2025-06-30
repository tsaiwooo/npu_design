`timescale 1ns / 1ps
`include "params.vh"
// we can add arbiter to eliminate the conflict between different modules
module sram_controller# ( parameter C_AXIS_TDATA_WIDTH = 64)
(
    input clk,
    input rst,

    // GEMM1 port
    input [MAX_ADDR_WIDTH-1:0] gemm1_addr,
    input [C_AXIS_TDATA_WIDTH-1:0] gemm1_data_in,
    input  gemm1_en,
    input  gemm1_we,
    input [2:0] gemm1_idx,
    output signed [SRAM_WIDTH_O-1:0] gemm1_data_out,

    // GEMM2 port
    input [MAX_ADDR_WIDTH-1:0] gemm2_addr,
    input [C_AXIS_TDATA_WIDTH-1:0] gemm2_data_in,
    input  gemm2_en,
    input  gemm2_we,
    input [2:0] gemm2_idx,
    output signed [SRAM_WIDTH_O-1:0] gemm2_data_out,
    
    // ELEM port
    input [MAX_ADDR_WIDTH-1:0] elem_addr,
    input signed [C_AXIS_TDATA_WIDTH-1:0] elem_data_in,
    input  elem_en,
    input  elem_we,
    input [2:0] elem_idx,
    output signed [SRAM_WIDTH_O-1:0] elem_data_out,

    // axi4 input port
    input [MAX_ADDR_WIDTH-1:0] write_address,
    input [C_AXIS_TDATA_WIDTH-1:0] write_data,
    input [2:0] axi_idx,
    input write_enable,

    // axi4 output port
    input sram_out_en,
    input [2:0] sram_out_idx,
    input [MAX_ADDR_WIDTH-1:0] sram_out_addr,
    output signed [SRAM_WIDTH_O-1:0] sram_out_data,

    // op0 weight access sram
    input op0_weight_sram_en,
    input [MAX_ADDR_WIDTH-1:0] op0_weight_sram_addr_i,
    input [2:0] op0_weight_sram_idx,
    output [C_AXIS_TDATA_WIDTH-1:0] op0_weight_sram_data_o,

    // op0 data access sram
    input op0_data_sram_en,
    input [MAX_ADDR_WIDTH-1:0] op0_data_sram_addr_i,
    input [2:0] op0_data_sram_idx,
    output [C_AXIS_TDATA_WIDTH-1:0] op0_data_sram_data_o,

    // store op result to sram
    input result_sram_en,
    input result_sram_we,
    input [MAX_ADDR_WIDTH-1:0] result_sram_addr_i,
    input [2:0] result_sram_idx,
    input [C_AXIS_TDATA_WIDTH-1:0] result_sram_data_i,

    // sram access counts
    output reg [63:0] total_mem_access_counts,
    output reg [63:0] store_access_sram_counts
);
    reg [3:0] mem_access_this_cycle;
    reg [NUM_SRAMS-1:0] en;
    reg [NUM_SRAMS-1:0] we;
    reg [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr;
    reg [NUM_SRAMS * C_AXIS_TDATA_WIDTH - 1 : 0] data_in;
    wire [NUM_SRAMS * SRAM_WIDTH_O - 1 : 0] data_out;
    reg signed [SRAM_WIDTH_O-1:0] each_data_out[NUM_SRAMS];

    // arbiter: en、we、addr、data_in and send to multi_sram
    reg [NUM_SRAMS-1:0] arb_we;
    reg [NUM_SRAMS-1:0] arb_en;
    reg [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] arb_addr;
    reg [NUM_SRAMS * C_AXIS_TDATA_WIDTH - 1 : 0] arb_data_in;

    assign gemm1_data_out = each_data_out[gemm1_idx];
    assign gemm2_data_out = each_data_out[gemm2_idx];
    assign elem_data_out = each_data_out[elem_idx];
    assign sram_out_data = each_data_out[sram_out_idx];
    assign op0_weight_sram_data_o = each_data_out[op0_weight_sram_idx];
    assign op0_data_sram_data_o = each_data_out[op0_data_sram_idx];

    integer i,sram_idx;
    always @(*)begin
        for(i = 0; i < NUM_SRAMS; i = i + 1)begin
            each_data_out[i] = data_out[i * SRAM_WIDTH_O +: SRAM_WIDTH_O];
        end
    end

    always @(*) begin
        arb_we = {NUM_SRAMS{1'b0}};
        arb_en = {NUM_SRAMS{1'b0}};
        arb_addr = {NUM_SRAMS * MAX_ADDR_WIDTH{1'b0}};
        arb_data_in = {NUM_SRAMS * C_AXIS_TDATA_WIDTH{1'b0}};
        // determine which sram to write and arbiter
        for (sram_idx = 0; sram_idx < NUM_SRAMS; sram_idx = sram_idx + 1) begin
            // priority: result_sram >  op0_weight > op0_data > op1_data > op2_data > op3_data > elem > gemm1 > gemm2 > axi >　axi4_output port
            if(result_sram_we && result_sram_idx == sram_idx)begin
                arb_we[sram_idx] = 1'b1;
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = result_sram_addr_i;
                arb_data_in[sram_idx * C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] = result_sram_data_i;
                // $display("result_sram_we");
            end
            else if(gemm1_en && gemm1_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = gemm1_addr;
            end
            else if(gemm2_en && gemm2_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = gemm2_addr;
            end
            else if(op0_weight_sram_en && op0_weight_sram_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = op0_weight_sram_addr_i;
                // $display("op0_weight_sram_en, addr = %d, data = %h", op0_weight_sram_addr_i, op0_weight_sram_data_o);
            end
            else if(op0_data_sram_en && op0_data_sram_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = op0_data_sram_addr_i;
                // $display("op0_data_sram_en, addr = %d, data = %h", op0_data_sram_addr_i, op0_data_sram_data_o);
            end
            else if(elem_en && elem_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = elem_addr;
            end
            else if(write_enable && axi_idx == sram_idx)begin
                arb_we[sram_idx] = 1'b1;
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = write_address;
                arb_data_in[sram_idx * C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] = write_data;
                // $display("Writing weight data to SRAM[%d], address = %d, data = %h",axi_idx, write_address, write_data);
            end
            else if(sram_out_en && sram_out_idx == sram_idx)begin
                arb_en[sram_idx] = 1'b1;
                arb_addr[sram_idx * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = sram_out_addr;
                // $display("sram_out_en, addr = %d, data = %h", sram_out_addr, sram_out_data);
            end
        end
    end

    always @(*)begin
        en = arb_en;
        we = arb_we;
        addr = arb_addr;
        data_in = arb_data_in;
    end

    integer j;
    always @(*) begin
        mem_access_this_cycle = 0;
        for (j = 0; j < 8; j = j + 1)
            mem_access_this_cycle = mem_access_this_cycle + en[j];
    end
    always @(posedge clk)begin
        if(!rst) begin
            total_mem_access_counts <= 0;
        end else begin
            total_mem_access_counts <= total_mem_access_counts + mem_access_this_cycle;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            store_access_sram_counts <= 0;
        end else begin
            if (result_sram_we && (op0_data_sram_en || gemm1_en)) begin
                store_access_sram_counts <= store_access_sram_counts + 2'd2;
            end else if(op0_data_sram_en || gemm1_en) begin
                store_access_sram_counts <= store_access_sram_counts + 2'd1;
            end else if (result_sram_we) begin
                store_access_sram_counts <= store_access_sram_counts + 1'd1;
            end 
        end
    end
    
    // control SRAM
    multi_sram #(.DATA_WIDTH(64)) multi_sram_gen (
        .clk(clk),
        .rst(rst),
        .en(en),
        .we(we),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

endmodule