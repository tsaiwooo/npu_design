`timescale 1ns / 1ps

module arbiter#
(
    
)
(
    input clk,
    input arst,
    input [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr_axi4;
    input [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr_GEMM;
    input [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr_ELEM;
    input [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr_quant;
    input [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_axi4_i;
    input [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_GEMM_i;
    input [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_ELEN_i;
    input [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_quant_i;
    output 
)

    // sram input and output signals
    reg [NUM_SRAMS-1:0] en;
    reg [NUM_SRAMS-1:0] we;
    // reg [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr;
    reg [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_in;
    wire [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_out;

    // sram_img and sram_ker port2 for enable read sram
    always @(*)begin
        we = {NUM_SRAMS{1'b0}};
        // if(s00_axis_tvalid & s00_axis_tready & (state==LOAD_IMG))begin
        if((s00_axis_tvalid & s00_axis_tready && (ST_state==ST_IMG)))begin
            we[GEMM0_SRAM_IDX] = 1'b1;
        end
        // if(s00_axis_tvalid & s00_axis_tready & (state==LOAD_KER))begin
        if((s00_axis_tvalid & s00_axis_tready && (ST_state==ST_KER)))begin
            we[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(read_sram_enable)begin
            we[ELEM0_SRAM_IDX] = 1'b0;
        end else if(mac_valid_out)begin
            we[ELEM0_SRAM_IDX] = 1'b1;
        end
    end

    always @(*)begin
        en = {NUM_SRAMS{1'b0}};
        if(we[GEMM0_SRAM_IDX])begin
            en[GEMM0_SRAM_IDX] = 1'b1;
        end
        if(we[GEMM1_SRAM_IDX])begin
            en[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(state == COMPUTE_CONV0)begin
            en[GEMM0_SRAM_IDX] = 1'b1;
            en[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(mac_valid_out || read_sram_enable)begin
            en[ELEM0_SRAM_IDX] = 1'b1;
        end
    end

    always @(*) begin
        addr = {NUM_SRAMS * MAX_ADDR_WIDTH{1'b0}};  // 初始化為 0

        if(en[GEMM0_SRAM_IDX] && state == COMPUTE_CONV0) begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = (conv_row + for_conv_row) * img_col_reg + conv_col + for_conv_col;
        end else if(en[GEMM0_SRAM_IDX]) begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_img;
        end

        if(en[GEMM1_SRAM_IDX] && state == COMPUTE_CONV0) begin
            addr[GEMM1_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = for_conv_row * ker_col_reg + for_conv_col;
        end else if(en[GEMM1_SRAM_IDX]) begin
            addr[GEMM1_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_ker;
        end

        if(en[ELEM0_SRAM_IDX] && read_sram_enable)begin
            addr[ELEM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = read_idx;
        end else if(en[ELEM0_SRAM_IDX]) begin
            addr[ELEM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_out;
        end 
        
        // ********************** MODIFY
        // if(m00_axis_tready && m00_axis_tvalid)begin
        if(read_sram_enable)begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = read_idx;
        end
        // ********************** MODIFY
    end

    // sram input data
    always @(*)begin
        data_in = {NUM_SRAMS * MAX_DATA_WIDTH{1'b0}};
        if(we[GEMM0_SRAM_IDX])begin
            data_in[GEMM0_SRAM_IDX * MAX_DATA_WIDTH  +: C_AXIS_TDATA_WIDTH] =  s00_axis_tdata;
        end
        if(we[GEMM1_SRAM_IDX])begin
            data_in[GEMM1_SRAM_IDX * MAX_DATA_WIDTH +: C_AXIS_TDATA_WIDTH] =  s00_axis_tdata;
        end
        if(mac_valid_out)begin
            data_in[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH] = mac_out;
        end
    end
endmodule