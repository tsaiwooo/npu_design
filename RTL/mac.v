`timescale 1ns / 1ps
`define SIMULATION

module mac#
(
    parameter MAX_MACS = 64,
    parameter DATA_WIDTH = 8,
    parameter MAX_GROUPS = 8,
    parameter MAC_BIT_PER_GROUP = 7
)
(
    input                                    clk,         
    input                                    rst,         
    input      [3:0]   num_groups,
    input      [MAX_GROUPS * MAC_BIT_PER_GROUP -1:0]     num_macs_i,  
    input                                    valid_in,   
    input       [MAX_MACS*DATA_WIDTH-1:0]    data,  
    input       [MAX_MACS*DATA_WIDTH-1:0]    weight,
    output reg signed [MAX_GROUPS*4*INT8_SIZE-1:0]       mac_out, // 32bits is the result bandwidth
    output reg                               valid_out,
    output reg [3:0] num_groups_o
);

reg signed [2*DATA_WIDTH-1:0] mac_result[0:MAX_MACS-1];
reg signed [4*DATA_WIDTH-1:0] sum_result[0:MAX_GROUPS-1];
integer i,j;
reg [6:0] group_macs[0:MAX_GROUPS-1];
reg result_out;

reg [$clog2(MAX_GROUPS+1) -1:0] num_groups_reg;

integer group_idx, pe_idx;

// pipeline register for num_groups
reg [3:0] num_groups_pipeline[0:1];

always @(posedge clk)begin
    if(!rst)begin
        num_groups_pipeline[0] <= 0;
        num_groups_pipeline[1] <= 0;
    end else begin
        num_groups_pipeline[0] <= num_groups;
        num_groups_pipeline[1] <= num_groups_pipeline[0];
    end
end

always @(posedge clk)begin
    if(!rst)begin
        num_groups_o <= 0;
    end else begin
        num_groups_o <= num_groups_pipeline[0];
    end
end

always @(*)begin
    if(!rst)begin
        num_groups_reg = 0;
    end else if(valid_in) begin
        num_groups_reg = num_groups;
    end
end

// always @(*)begin
//     for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
//         group_macs[group_idx] = 0;
//     end
//     if(valid_in) begin
//         for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
//             group_macs[group_idx] = num_macs_i[group_idx*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP];
//         end
//     end
// end

always @(posedge clk)begin
    if(!rst) begin
        for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
            group_macs[group_idx] <= 0;
        end
    end if(valid_in) begin
        for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
            group_macs[group_idx] <= num_macs_i[group_idx*MAC_BIT_PER_GROUP +: MAC_BIT_PER_GROUP];
        end
    end
end

reg [9:0] start_idx; 
reg [9:0] group_start_addr[0:MAX_GROUPS-1]; // store group start address

always @(*) begin
    if(!rst)begin
        start_idx = 0;  // initialize start_idx
    end else if(valid_in) begin
        // start calcuate group address
        start_idx = 0;  // initialize start_idx
        for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
            group_start_addr[group_idx] = start_idx; // record current group start address
            
            // update start_idx，add current group  MAC number
            start_idx = start_idx + group_macs[group_idx];  // each MAC occupy DATA_WIDTH bandwidth
            // $display("group_start_addr[%0d] = %0d", group_idx, group_start_addr[group_idx]);
        end
    end else begin
        start_idx = 0;  // initialize start_idx
        for (group_idx = 0; group_idx < MAX_GROUPS; group_idx = group_idx + 1) begin
            group_start_addr[group_idx] = 0; // record current group start address
        end
    end
end


reg valid_pipeline [1:0];
always @(posedge clk) begin
    if (!rst) begin
        valid_pipeline[0] <= 0;
        valid_pipeline[1] <= 0;
    end else begin
        valid_pipeline[0] <= valid_in;
        valid_pipeline[1] <= valid_pipeline[0];
    end
end

// wire gated_clk1, gated_clk2;
// `ifdef SIMULATION
//     // simulation use
//     assign gated_clk1 = clk & valid_in;
//     assign gated_clk2 = clk & valid_pipeline[0];
// `else
//     // standard cell cg_cell
//     cg_cell u_cg_cell1 (
//         .clk_in (clk),
//         .en     (valid_in),
//         .clk_out(gated_clk1)
//     );

//     cg_cell u_cg_cell2 (
//         .clk_in (clk),
//         .en     (valid_pipeline[0]),
//         .clk_out(gated_clk2)
//     );
// `endif

// Generate MAC calculations
always @(posedge clk) begin
    if (!rst) begin
        for (i = 0; i < MAX_MACS; i = i + 1) begin
            mac_result[i] <= 0;
        end
    end else if (valid_in) begin
        // $display("MAC calculation data: %h, weight: %h", data, weight);
        for (i = 0; i < MAX_MACS; i = i + 1) begin
            mac_result[i] <= $signed(data[i*DATA_WIDTH +: DATA_WIDTH]) * $signed(weight[i*DATA_WIDTH +: DATA_WIDTH]);
        end
    end
end

// sum_stage of each group
generate
    genvar group_idx_g, i_g;
    for (group_idx_g = 0; group_idx_g < MAX_GROUPS; group_idx_g = group_idx_g + 1) begin : sum_group_gen
        wire signed [4*DATA_WIDTH-1:0] sum_stage_1 [0:(MAX_MACS>>1)-1];
        wire signed [4*DATA_WIDTH-1:0] sum_stage_2 [0:(MAX_MACS>>2)-1];
        wire signed [4*DATA_WIDTH-1:0] sum_stage_3 [0:(MAX_MACS>>3)-1];
        wire signed [4*DATA_WIDTH-1:0] sum_stage_4 [0:(MAX_MACS>>4)-1];
        wire signed [4*DATA_WIDTH-1:0] sum_stage_5 [0:(MAX_MACS>>5)-1];
        wire signed [4*DATA_WIDTH-1:0] sum_stage_6 [0:(MAX_MACS>>6)-1];

        // Stage 1: Sum adjacent pairs for the current group
        for (i_g = 0; i_g < MAX_MACS >> 1; i_g = i_g + 1) begin : sum_gen_1
            assign sum_stage_1[i_g] = ((2*i_g + 1) < group_macs[group_idx_g]) ? 
                                    mac_result[2*i_g + group_start_addr[group_idx_g] ] + mac_result[2*i_g + 1 + group_start_addr[group_idx_g]] : 
                                    mac_result[2*i_g + group_start_addr[group_idx_g] ];  // Odd case: pass through the last element
        end

        // Stage 2: Sum results from stage 1 for the current group
        for (i_g = 0; i_g < MAX_MACS >> 2; i_g = i_g + 1) begin : sum_gen_2
            assign sum_stage_2[i_g] = ((2*i_g + 1) < ((group_macs[group_idx_g] + 1) >> 1)) ? 
                                    sum_stage_1[2*i_g] + sum_stage_1[2*i_g + 1] : 
                                    sum_stage_1[2*i_g];  // Odd case: pass through the last element
        end

        // Stage 3: Sum results from stage 2 for the current group
        for (i_g = 0; i_g < MAX_MACS >> 3; i_g = i_g + 1) begin : sum_gen_3
            assign sum_stage_3[i_g] = ((2*i_g + 1) < ((group_macs[group_idx_g] + 3) >> 2)) ? 
                                    sum_stage_2[2*i_g] + sum_stage_2[2*i_g + 1] : 
                                    sum_stage_2[2*i_g];  // Odd case: pass through the last element
        end

        // Stage 4: Sum results from stage 3 for the current group
        for (i_g = 0; i_g < MAX_MACS >> 4; i_g = i_g + 1) begin : sum_gen_4
            assign sum_stage_4[i_g] = ((2*i_g + 1) < ((group_macs[group_idx_g] + 7) >> 3)) ? 
                                    sum_stage_3[2*i_g] + sum_stage_3[2*i_g + 1] : 
                                    sum_stage_3[2*i_g];  // Odd case: pass through the last element
        end

        // Stage 5: Sum results from stage 4 for the current group
        for (i_g = 0; i_g < MAX_MACS >> 5; i_g = i_g + 1) begin : sum_gen_5
            assign sum_stage_5[i_g] = ((2*i_g + 1) < ((group_macs[group_idx_g] + 15) >> 4)) ? 
                                    sum_stage_4[2*i_g] + sum_stage_4[2*i_g + 1] : 
                                    sum_stage_4[2*i_g];  // Odd case: pass through the last element
        end

        // Stage 6: Sum results from stage 5 for the current group
        for (i_g = 0; i_g < MAX_MACS >> 6; i_g = i_g + 1) begin : sum_gen_6
            assign sum_stage_6[i_g] = ((2*i_g + 1) < ((group_macs[group_idx_g] + 31) >> 5)) ? 
                                    sum_stage_5[2*i_g] + sum_stage_5[2*i_g + 1] : 
                                    sum_stage_5[2*i_g];  // Odd case: pass through the last element
        end

        // store final result 
        always @(posedge clk) begin
            if (valid_pipeline[0]) begin
                if (group_macs[group_idx_g] <= 1) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= mac_result[group_start_addr[group_idx_g]]; // For 1 MAC
                end else if (group_macs[group_idx_g] <= 2) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_1[0];
                end else if (group_macs[group_idx_g] <= 4) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_2[0];
                end else if (group_macs[group_idx_g] <= 8) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_3[0];
                end else if (group_macs[group_idx_g] <= 16) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_4[0];
                end else if (group_macs[group_idx_g] <= 32) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_5[0];
                end else if (group_macs[group_idx_g] <= 64) begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= sum_stage_6[0];
                end else begin
                    mac_out[group_idx_g*4*DATA_WIDTH +: 4*DATA_WIDTH] <= 0;
                end
            end
        end
    end
endgenerate


// control valid out
always @(posedge clk)begin
    if (!rst)begin
        valid_out <= 0;
    end else begin
        valid_out <= valid_pipeline[0];
    end
end

endmodule // mac