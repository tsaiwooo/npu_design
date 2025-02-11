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