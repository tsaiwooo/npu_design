`timescale 1ns / 1ps

module mac#
(
    parameter MAX_MACS = 32,
    parameter DATA_WIDTH = 8
)
(
    input                                   clk,         
    input                                   rst,         
    input      [6:0]                        num_macs_i,  
    input                                   valid_in,   
    input      [MAX_MACS*DATA_WIDTH-1:0]    data,  
    input      [MAX_MACS*DATA_WIDTH-1:0]    weight,
    output reg [2*DATA_WIDTH-1:0]           mac_out, 
    output reg                              valid_out 
);

localparam mul_st1 = 2'd1;
localparam add_st2 = 2'd2;
reg [1:0] st = 2'b0;

reg [2*DATA_WIDTH-1:0] mac_result [MAX_MACS-1:0];
reg [2*DATA_WIDTH-1:0] sum_result;
integer i;
wire [6:0] macs;
reg result_out;
assign macs = num_macs_i;

// control stage
always@(posedge clk or posedge rst) begin
    if (rst) begin
        st <= mul_st1;
    end else begin
        case (st)
            mul_st1: begin
                if (valid_in && macs > 0 && macs <= MAX_MACS) begin
                    st <= add_st2;
                end
            end
            add_st2: begin
                if (result_out) begin
                    st <= mul_st1;
                end
            end
            default: st <= mul_st1;
        endcase
    end
end


// Generate MAC calculations
generate
    genvar idx;
    for (idx = 0; idx < MAX_MACS; idx = idx + 1) begin : mac_gen
        always @(posedge clk or posedge rst) begin
            if (rst) begin
                mac_result[idx] <= 0;
            end else if (valid_in) begin
                if (idx < macs) begin
                    mac_result[idx] <= data[DATA_WIDTH*idx +: DATA_WIDTH] * weight[DATA_WIDTH*idx +: DATA_WIDTH];
                end else begin
                    mac_result[idx] <= 0;
                end
            end
        end
    end
endgenerate

// Reduction tree for summation with support for 1 to 32 MACs
wire [2*DATA_WIDTH-1:0] sum_stage_1 [MAX_MACS/2-1:0];
wire [2*DATA_WIDTH-1:0] sum_stage_2 [MAX_MACS/4-1:0];
wire [2*DATA_WIDTH-1:0] sum_stage_3 [MAX_MACS/8-1:0];
wire [2*DATA_WIDTH-1:0] sum_stage_4 [MAX_MACS/16-1:0];
wire [2*DATA_WIDTH-1:0] sum_stage_5 [MAX_MACS/32-1:0];
wire [2*DATA_WIDTH-1:0] sum_stage_6 [MAX_MACS/64-1:0];

// Stage 1: Sum adjacent pairs, handle odd number of macs
generate
    for (idx = 0; idx < MAX_MACS/2; idx = idx + 1) begin : sum_gen_1
        assign sum_stage_1[idx] = ((2*idx + 1) < macs) ? 
                                  mac_result[2*idx] + mac_result[2*idx + 1] : 
                                  mac_result[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Stage 2: Sum results from stage 1, handle odd number of results
generate
    for (idx = 0; idx < MAX_MACS/4; idx = idx + 1) begin : sum_gen_2
        assign sum_stage_2[idx] = ((2*idx + 1) < (macs + 1) / 2) ? 
                                  sum_stage_1[2*idx] + sum_stage_1[2*idx + 1] : 
                                  sum_stage_1[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Stage 3: Sum results from stage 2, handle odd number of results
generate
    for (idx = 0; idx < MAX_MACS/8; idx = idx + 1) begin : sum_gen_3
        assign sum_stage_3[idx] = ((2*idx + 1) < (macs + 3) / 4) ? 
                                  sum_stage_2[2*idx] + sum_stage_2[2*idx + 1] : 
                                  sum_stage_2[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Stage 4: Sum results from stage 3, handle odd number of results
generate
    for (idx = 0; idx < MAX_MACS/16; idx = idx + 1) begin : sum_gen_4
        assign sum_stage_4[idx] = ((2*idx + 1) < (macs + 7) / 8) ? 
                                  sum_stage_3[2*idx] + sum_stage_3[2*idx + 1] : 
                                  sum_stage_3[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Stage 5: Sum results from stage 4, handle odd number of results
generate
    for (idx = 0; idx < MAX_MACS/32; idx = idx + 1) begin : sum_gen_5
        assign sum_stage_5[idx] = ((2*idx + 1) < (macs + 15) / 16) ? 
                                  sum_stage_4[2*idx] + sum_stage_4[2*idx + 1] : 
                                  sum_stage_4[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Stage 6: Sum results from stage 5, handle odd number of results
generate
    for (idx = 0; idx < MAX_MACS/64; idx = idx + 1) begin : sum_gen_6
        assign sum_stage_6[idx] = ((2*idx + 1) < (macs + 31) / 32) ? 
                                  sum_stage_5[2*idx] + sum_stage_5[2*idx + 1] : 
                                  sum_stage_5[2*idx];  // Odd case: pass through the last element
    end
endgenerate

// Select the final summation result based on the number of MACs
always @(posedge clk or posedge rst) begin
    if (st == add_st2 && macs == 1) begin
        sum_result <= mac_result[0];
    end else if (st == add_st2 && macs <= 2) begin
        sum_result <= sum_stage_1[0];
    end else if (st == add_st2 && macs <= 4) begin
        sum_result <= sum_stage_2[0];
    end else if (st == add_st2 && macs <= 8) begin
        sum_result <= sum_stage_3[0];
    end else if (st == add_st2 && macs <= 16) begin
        sum_result <= sum_stage_4[0];
    end else if (st == add_st2 && macs <= 32) begin
        sum_result <= sum_stage_5[0];
    end  else if (st == add_st2 && macs <= 64) begin
        sum_result <= sum_stage_6[0];
    end else begin
        sum_result <= 0;
    end
end

// control result_out signal
always @(posedge clk or posedge rst) begin
    if (rst) begin
        result_out <= 0;
    end else begin
        result_out <= 0; // Reset result_out each cycle
        if (st == add_st2 && macs == 1) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 2) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 4) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 8) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 16) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 32) begin
            result_out <= 1;
        end else if (st == add_st2 && macs <= 64) begin
            result_out <= 1;
        end
    end
end


// Output logic
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mac_out <= 0;
    end
    else if (result_out) begin
        mac_out <= sum_result;
    end
end

// control valid out
always @(posedge clk)begin
    if (rst)begin
        valid_out <= 0;
    end else if(result_out) begin
        valid_out <= 1'b1;
    end else begin
        valid_out <= 1'b0;
    end
end

endmodule // mac