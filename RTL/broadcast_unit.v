// -----------------------------------------------------------
// broadcast_unit
// description: broadcast weight or data from sram
// 1. cache inside, store in one cycle
// 2. wrap-around
// 3. start_index store index and update each time
// -----------------------------------------------------------
`timescale 1ns / 1ps
`include "params.vh"

module broadcast_unit#(
    parameter MAX_VECTOR_SIZE = 8
)
(
    input clk,
    input rst,
    input init,
    input valid_i,
    input en,
    input [INT8_SIZE*8-1:0] data_i,
    input [MAX_ADDR_WIDTH-1:0] addr_i,
    input [INT32_SIZE-1:0] number_of_elements_i,
    output reg valid_o,
    output reg [8*INT8_SIZE-1:0] data_o
);
    
    reg [INT8_SIZE-1:0] cache[0:511];
    reg cache_valid[0:511];
    reg [MAX_ADDR_WIDTH-1:0] start_index;
    reg [MAX_ADDR_WIDTH-1:0] broadcast_start_index;
    reg [MAX_ADDR_WIDTH-1:0] cur_idx[0:MAX_VECTOR_SIZE-1];
    integer idx,j,k,m;

    // store data
    always @(posedge clk) begin
        if(!rst) begin
            for(idx = 0; idx<512; idx = idx + 1) begin
                cache[idx] <= 0;
            end
            // cache <= 0;
        end else if(init) begin
            for(idx = 0; idx<8 ; idx = idx + 1) begin
                cache[addr_i+idx] <= data_i[idx*INT8_SIZE +: INT8_SIZE];
            end
        end else if(valid_i) begin
            for(idx = 0; idx<8 ; idx = idx + 1) begin
                cache[addr_i+idx] <= data_i[idx*INT8_SIZE +: INT8_SIZE];
            end
        end
            // cache[addr_i*INT8_SIZE +: INT8_SIZE*8]  <= data_i;
    end

    // cache valid
    always @(posedge clk) begin
        if(!rst) begin
            // cache_valid <= 0;
            for(k = 0; k<512; k = k + 1) begin
                cache_valid[k] <= 0;
            end
        end else if(init) begin
            for(k = 0; k<8 ; k = k + 1) begin
                cache_valid[k] <= 0;
            end
        end else if(valid_i) begin
            for(k = 0; k<8 ; k = k + 1) begin
                cache_valid[addr_i+k] <= 1'b1;
            end
            // cache_valid[addr_i +: INT8_SIZE] <= 8'b11111111;
        end
    end 

    // control start_index
    always @(posedge clk) begin
        if(!rst) begin
            start_index <= 0;
        end else if(init) begin
            start_index <= 0;
        end else if(en) begin
            start_index <= (number_of_elements_i==1'd1)? 0: mod_func(start_index+MAX_VECTOR_SIZE,number_of_elements_i);
            // start_index <= (start_index+MAX_VECTOR_SIZE) % number_of_elements_i;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            broadcast_start_index <= 0;
        end else if(init) begin
            broadcast_start_index <= 0; 
        end else begin
            broadcast_start_index <= start_index;
        end
    end

    // calculate cur_idx
    always @(posedge clk) begin
        if(!rst)begin
            for(j = 0; j < MAX_VECTOR_SIZE; j = j + 1) begin
                cur_idx[j] <= 0;
            end
        end else if(init) begin
             for(j = 0; j < MAX_VECTOR_SIZE; j = j + 1) begin
                cur_idx[j] <= 0;
            end
        end else begin
            for(j = 0; j < MAX_VECTOR_SIZE; j = j + 1) begin
                cur_idx[j] <= (number_of_elements_i == 1'd1)? 1'b0: mod_func((broadcast_start_index+j) , number_of_elements_i);
                // cur_idx[j] <= (broadcast_start_index+j) % number_of_elements_i;
            end
        end
    end

    // output data depend on start_index and supports wrap-around
    // genvar i;
    // generate
    //     for(i = 0; i < MAX_VECTOR_SIZE; i = i + 1) begin : output_gen
    //         wire [MAX_ADDR_WIDTH-1:0] cur_idx_gen;
    //         // assign cur_idx = mod_func(broadcast_start_index+i,number_of_elements_i);
    //         // assign cur_idx = (broadcast_start_index+i) % number_of_elements_i;
    //         assign cur_idx_gen = cur_idx[i];
    //         // assign data_o[i*INT8_SIZE +: INT8_SIZE] = (cache_valid[cur_idx_gen] && en)? cache[cur_idx_gen*INT8_SIZE +: INT8_SIZE] : 
    //         assign data_o[i*INT8_SIZE +: INT8_SIZE] = (cache_valid[cur_idx_gen] && en)? cache[cur_idx_gen] : 
    //                                                   (en && cur_idx_gen < MAX_VECTOR_SIZE)? data_i[cur_idx_gen*INT8_SIZE +: INT8_SIZE]: 
    //                                                   (en)? data_i[i*INT8_SIZE +: INT8_SIZE] : 0;
    //         // assign data_o[i*INT8_SIZE +: INT8_SIZE] = cache[cur_idx*INT8_SIZE +: INT8_SIZE];
    //     end
    // endgenerate
    always @* begin
        for (m = 0; m < MAX_VECTOR_SIZE; m = m + 1)
            data_o[m*INT8_SIZE +: INT8_SIZE] = '0;

        if (en) begin
            for (m = 0; m < MAX_VECTOR_SIZE; m = m + 1) begin
                // cur_idx[m] 讀一次存到暫存線路，避免重算
                logic [MAX_ADDR_WIDTH-1:0] idx_lcl;
                idx_lcl = cur_idx[m];

                if (cache_valid[idx_lcl])
                    data_o[m*INT8_SIZE +: INT8_SIZE] = cache[idx_lcl];
                else if (idx_lcl < MAX_VECTOR_SIZE)
                    data_o[m*INT8_SIZE +: INT8_SIZE] = data_i[idx_lcl*INT8_SIZE +: INT8_SIZE];
                else
                    data_o[m*INT8_SIZE +: INT8_SIZE] = data_i[m*INT8_SIZE +: INT8_SIZE];
            end
        end
    end

    // output valid signal
    always @(posedge clk) begin
        if(!rst) begin
            valid_o <= 0;
        end else if(init) begin
            valid_o <= 0; 
        end else begin
            valid_o <= en;
        end 
    end
    // assign valid_o = en;

    always @(posedge clk) begin
        // if(en) $display("[BROADCAST_UNIT] broadcast start index = %d, broadcast data = %h", broadcast_start_index, data_o);
    end
endmodule