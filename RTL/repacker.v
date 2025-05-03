// ----------------------------------
// Repacker, a module that accumulate output from different engine, that can be stored into sram- 64bits 
// ----------------------------------
`timescale 1ns/1ps
`include "params.vh"

module repacker #(
    parameter OUTPUT_WIDTH = 64,
    parameter TOTAL_BTYES = 8,
    parameter ACCU_WIDTH = 128
)
(
    input clk,
    input rst,
    input in_valid,
    input tlast_i,
    input [OUTPUT_WIDTH-1:0] data_i,
    input [TOTAL_BTYES-1:0]  valid_mask,
    output reg [OUTPUT_WIDTH-1:0] data_o,
    output reg out_valid
);
    // accumlate valid data and data counts
    reg [ACCU_WIDTH-1:0] accumulator;
    // count the number of valid data currently in accumulator
    reg [6:0] count;

    // sequence pack data
    reg [ACCU_WIDTH-1:0] appended;
    reg [7:0] new_byte_count;

    integer i;
    always @(*)begin
        if(in_valid) begin
            appended = 0;
            new_byte_count = 0;
            for(i = 0; i < TOTAL_BTYES; i = i + 1)begin
                if(valid_mask[i])begin
                    appended =  appended | (data_i[8*i +: 8] << (8 * i));
                    new_byte_count = new_byte_count + 1;
                end
            end
        end 
        else begin
            appended = 0;
            new_byte_count = 0;
        end
    end

    // update accumulator with current data
    wire [ACCU_WIDTH-1:0] accu_combined = accumulator | (appended << (count * 8));
    wire [6:0] count_combined = count + new_byte_count;

    // flush_ready: when the accumulator is full or tlast_i is high
    wire flush_ready = (count_combined >= TOTAL_BTYES) || (tlast_i && (count_combined > 0));

    // ----------------------------------
    // update accumulator
    // ----------------------------------
    always @(posedge clk)begin
        if(!rst)begin
            accumulator <= 0;
        end
        else if(in_valid)begin
            if(flush_ready)begin
                accumulator <= accu_combined >> ( 8 * ((count_combined >= 8) ? 8 : count_combined));
            end
            else begin
                accumulator <= accu_combined;
            end
        end else if(tlast_i)begin
            accumulator <= 0;
        end
    end

    // ----------------------------------
    // update count
    // ----------------------------------
    always @(posedge clk)begin
        if(!rst)begin
            count <= 0;
        end
        else if(in_valid)begin
            if(tlast_i) begin
                count <= 0;
            end else if(flush_ready)begin
                count <= count_combined - ((count_combined >= TOTAL_BTYES) ? TOTAL_BTYES : 0);
            end else begin
                count <= count_combined;
            end
        end else if(flush_ready)begin
            count <= 0;
        end
    end

    // ----------------------------------
    // output data & valid
    // ----------------------------------
    always @(posedge clk)begin
        if(!rst)begin
            out_valid <= 0;
        end else if(flush_ready)begin
            out_valid <= 1;
        end else begin
            out_valid <= 0;
        end
    end
        
    always @(posedge clk)begin
        if(!rst)begin
            data_o <= 0;
        end else if(flush_ready)begin
            data_o <= accu_combined[OUTPUT_WIDTH-1:0];
        end
    end

endmodule