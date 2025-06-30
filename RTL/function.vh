`ifndef __FUNCTION_VH__
`define __FUNCTION_VH__
`include "params.vh"

function automatic signed [31:0] dequant_saturate(
    input signed [7:0] data_in,
    input signed [31:0] input_zero_point,
    input [31:0] input_range_radius
);
    reg signed [31:0] dequant_result;
begin
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;
    dequant_result = data_in - input_zero_point;
    if(dequant_result > $signed(input_range_radius))
        dequant_saturate = $signed(POS_127);
    else if(dequant_result < $signed(-input_range_radius))
        dequant_saturate = $signed(NEG_128);
    else 
        dequant_saturate = dequant_result;
end    

endfunction

function automatic [INT64_SIZE-1:0] get_specific_64bits(
    input [2*INT64_SIZE-1:0] data_in,
    input [MAX_ADDR_WIDTH-1:0] index
);
    reg [2:0] byte_offset;
    begin
        byte_offset = index[2:0];
        get_specific_64bits = data_in[INT8_SIZE*byte_offset +: INT64_SIZE];
    end
endfunction

function automatic [INT32_SIZE-1:0] mod_func(
    input [MAX_ADDR_WIDTH-1:0] index,
    input [INT32_SIZE-1:0] mod_value
);
    integer i;
    reg [INT32_SIZE-1:0] mod_result;
    begin
        mod_result = index;
        for(i = 0; i<10 && mod_result >= mod_value; i = i+1) begin
            mod_result = mod_result - mod_value;
        end
        mod_func = mod_result;
    end
endfunction
`endif // __FUNCTION_VH__
