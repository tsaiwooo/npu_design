// ************************************************
// run conv + requant + sram + dequant + exp + sram
// ************************************************


`timescale 1ns / 1ps

module tb_npu3();

//----------------------------------------------
// 1) Parameters
//----------------------------------------------
parameter PERIOD              = 10;
parameter MAX_MACS            = 64;
parameter ADDR_WIDTH          = 18;
parameter C_AXIS_TDATA_WIDTH  = 8;
parameter C_AXIS_MDATA_WIDTH  = 8;
parameter MAX_CHANNELS        = 64;
parameter NUM_CHANNELS_WIDTH  = $clog2(MAX_CHANNELS+1);
localparam signed [7:0] NEG_128 = -128;
localparam signed [7:0] POS_127 =  127;

// TB 裡用到: SHIFT 的常數
localparam signed NEG_12 = -12;

//----------------------------------------------
// 2) Variables
//----------------------------------------------
integer img_file, weight_file, scan_result;
reg [ADDR_WIDTH-1:0] img_row, img_col, ker_row, ker_col;
integer i, j, m, n;

//----------------------------------------------
// 3) Buffers and arrays
//----------------------------------------------

// (A) 存放 image / weight
reg signed [C_AXIS_TDATA_WIDTH-1:0] img_buffer    [0:2**ADDR_WIDTH-1];
reg signed [C_AXIS_TDATA_WIDTH-1:0] weight_buffer [0:2**ADDR_WIDTH-1];

// (B) 新增：保存「卷積尚未 Requant」(累加) 與「Requant 後」的預期值
reg signed [31:0] sum_before_requant [0:2**ADDR_WIDTH-1];  // Requant 前的累加
reg signed [C_AXIS_MDATA_WIDTH-1:0] expected_output [0:2**ADDR_WIDTH-1]; // Requant 後的結果
reg signed [31:0] exp_output [0:2**ADDR_WIDTH-1]; // dequant+exp 後的結果

//----------------------------------------------
// 4) Inputs to NPU
//----------------------------------------------
reg   s00_axis_aclk    = 1'b0;
reg   s00_axis_aresetn = 1;
reg   [C_AXIS_TDATA_WIDTH-1:0] s00_axis_tdata = 0;
reg   s00_axis_tvalid  = 0;
reg   s00_axis_tlast   = 0;
reg   [2*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser = 0;
reg   m00_axis_aclk    = 1'b0;
reg   m00_axis_aresetn = 1;
reg   m00_axis_tready  = 0;
reg   [31:0] input_range_radius = 480;
reg   signed [31:0] input_zero_point = -3;
reg   signed [31:0] input_left_shift = 22;
reg   signed [31:0] input_multiplier = 1591541760;

//----------------------------------------------
// 5) Requant 參數 (TB 中固定值)
//----------------------------------------------
reg [31:0]  test_q_multiplier = 32'd1388164317; 
reg signed [31:0] test_shift  = -9;

//----------------------------------------------
// 6) Outputs from NPU
//----------------------------------------------
wire  s00_axis_tready;
wire  signed [C_AXIS_MDATA_WIDTH-1:0] m00_axis_tdata;
wire  m00_axis_tstrb;
wire  m00_axis_tvalid;
wire  m00_axis_tlast;
wire  [NUM_CHANNELS_WIDTH-1:0] m00_axis_tuser;
wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0] dump; // unused
wire [31:0] cycle_count;

//----------------------------------------------
// 7) Clock generation
//----------------------------------------------
initial begin
    forever #(PERIOD/2) s00_axis_aclk = ~s00_axis_aclk;
end

initial begin
    forever #(PERIOD/2) m00_axis_aclk = ~m00_axis_aclk;
end

//----------------------------------------------
// 8) FSDB dump
//----------------------------------------------
initial begin
    $fsdbDumpfile("verdi.fsdb");
    $fsdbDumpvars(0, tb_npu3, "+all");
end

//----------------------------------------------
// 9) Reset logic
//----------------------------------------------
initial begin
    s00_axis_aresetn = 0;
    m00_axis_aresetn = 0;
    #(PERIOD*2);
    s00_axis_aresetn = 1;
    m00_axis_aresetn = 1;
    #(PERIOD*10);
end

//----------------------------------------------
// 10) Instantiate NPU
//----------------------------------------------
npu #(
    .MAX_MACS(MAX_MACS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .C_AXIS_TDATA_WIDTH(C_AXIS_TDATA_WIDTH),
    .C_AXIS_MDATA_WIDTH(C_AXIS_MDATA_WIDTH),
    .MAX_CHANNELS(MAX_CHANNELS),
    .NUM_CHANNELS_WIDTH(NUM_CHANNELS_WIDTH)
) u_npu (
    .s00_axis_aclk(s00_axis_aclk),
    .s00_axis_aresetn(s00_axis_aresetn),
    .s00_axis_tdata(s00_axis_tdata),
    .s00_axis_tvalid(s00_axis_tvalid),
    .s00_axis_tlast(s00_axis_tlast),
    .s00_axis_tuser(s00_axis_tuser),
    .s00_axis_tstrb(dump),
    .m00_axis_aclk(m00_axis_aclk),
    .m00_axis_aresetn(m00_axis_aresetn),
    .m00_axis_tready(m00_axis_tready),
    .s00_axis_tready(s00_axis_tready),
    .m00_axis_tdata(m00_axis_tdata),
    .m00_axis_tvalid(m00_axis_tvalid),
    .m00_axis_tlast(m00_axis_tlast),
    .m00_axis_tuser(m00_axis_tuser),
    .m00_axis_tstrb(m00_axis_tstrb),
    // Requant
    .quantized_multiplier(test_q_multiplier),
    .shift(test_shift),
    // dequant signals
    .input_range_radius(input_range_radius),
    .input_zero_point(input_zero_point),
    .input_left_shift(input_left_shift),
    .input_multiplier(input_multiplier),
    // cycle count for calculation
    .cycle_count(cycle_count)
);

//----------------------------------------------
// 11) Read image / weight data into buffers
//----------------------------------------------
initial begin
    img_file = $fopen("image_data.txt", "r");
    weight_file = $fopen("kerenl_data.txt", "r");

    // 讀取 image row/col
    scan_result = $fscanf(img_file, "%d %d\n", img_row, img_col);
    for (i = 0; i < img_row * img_col; i = i + 1) begin
        scan_result = $fscanf(img_file, "%d\n", img_buffer[i]);
    end

    // 讀取 weight row/col
    scan_result = $fscanf(weight_file, "%d %d\n", ker_row, ker_col);
    for (i = 0; i < ker_row * ker_col; i = i + 1) begin
        scan_result = $fscanf(weight_file, "%d\n", weight_buffer[i]);
    end

    $fclose(img_file);
    $fclose(weight_file);
end

//----------------------------------------------
// 12) 送出 image data
//----------------------------------------------
integer tmp;
task send_image;
begin
    $display("img_row = %d, img_col = %d, last = %d", img_row, img_col, img_row * img_col - 1);
    @(posedge s00_axis_aclk);
    for (i = 0; i < img_row * img_col; i = i + 1) begin
        s00_axis_tdata  = img_buffer[i];
        s00_axis_tvalid = 1;
        s00_axis_tlast  = (i == img_row * img_col - 1);
        tmp = 1;
        s00_axis_tuser  = {img_row, img_col, tmp[NUM_CHANNELS_WIDTH-1:0]};  // metadata in tuser
        wait(s00_axis_tready);
        @(posedge s00_axis_aclk);
    end
    s00_axis_tvalid = 0;
    s00_axis_tlast  = 0;
end
endtask

//----------------------------------------------
// 13) 送出 weight data
//----------------------------------------------
task send_weight;
begin
    $display("ker_row = %d, ker_col = %d, last = %d", ker_row, ker_col, ker_row * ker_col - 1);
    @(posedge s00_axis_aclk);
    for (i = 0; i < ker_row * ker_col; i = i + 1) begin
        s00_axis_tdata  = weight_buffer[i];
        s00_axis_tvalid = 1;
        s00_axis_tlast  = (i == ker_row * ker_col - 1);
        tmp = 1;
        s00_axis_tuser  = {ker_row, ker_col, tmp[NUM_CHANNELS_WIDTH-1:0]};
        wait(s00_axis_tready);
        @(posedge s00_axis_aclk);
    end
    s00_axis_tvalid = 0;
    s00_axis_tlast  = 0;
end
endtask

//----------------------------------------------
// 14) TB 端的 do_requant function
//----------------------------------------------
// Golden Model for reference calculation
function signed [31:0] golden_multiply_by_quantized_multiplier(
    input signed [31:0] x,
    input [31:0] quantized_multiplier,
    input signed [31:0] shift
);
    reg signed [63:0] ab_64;
    reg [31:0] remainder, threshold;
    reg [31:0] left_shift, right_shift;
    reg signed [31:0] ab_x2_high32;
    reg signed [30:0] nudge;
    reg [31:0] mask;
    reg overflow;
    reg signed [31:0] tmp_golden;
    
    begin
        // $display("start x = %d, quantized_multiplier = %d", x, quantized_multiplier);
        left_shift = (shift > 0) ? shift : 0;
        right_shift = (shift > 0) ? 0 : -shift;

        ab_64 = x * (64'sd1 << left_shift);
        // $display("before_ab_64 = %h", ab_64);
        ab_64 = ab_64 * quantized_multiplier;

        overflow = (x == quantized_multiplier && x == 32'h80000000);
        nudge = (ab_64 >= 0) ? (1 << 30) : (1 - (1 << 30));
        ab_x2_high32 = overflow ? 32'h7fffffff : (ab_64 + nudge) >>> 31;
        // $display("x = %d, quantized_multiplier = %d", x, quantized_multiplier);
        // $display("left_shift = %d, right_shift = %d", left_shift, right_shift);
        // $display("ab_64 = %h", ab_64);
        if (ab_64 < -128<<right_shift && right_shift) begin
            golden_multiply_by_quantized_multiplier = -8'd128;
        end else if (ab_64 > 127<<right_shift && right_shift) begin
            golden_multiply_by_quantized_multiplier = 8'd127;
        end else begin
            mask = (1 << right_shift) - 1;
            remainder = ab_x2_high32 & mask;
            // $display("ab_x2_high32 = %h, mask = %h, remainder = %h", ab_x2_high32, mask, remainder);
            threshold = mask >> 1;
            if (ab_x2_high32 < 0)
                threshold = threshold + 1;

            tmp_golden = ab_x2_high32 >> right_shift;
            // $display("golden_multiply_by_quantized_multiplier = %h", tmp_golden);
            if (remainder > threshold || 
                (remainder == threshold && (ab_x2_high32 & 1) && ab_x2_high32 != 32'h7fffffff)) begin
                    golden_multiply_by_quantized_multiplier = (tmp_golden >= $signed(POS_127))? POS_127:
                                                               (tmp_golden < $signed(NEG_128))? NEG_128: tmp_golden + 1;
            // else if(tmp_golden > 127)
            //     golden_multiply_by_quantized_multiplier = 127;
            // else if(tmp_golden < -128)
            //     golden_multiply_by_quantized_multiplier = -128;
            end else begin
                golden_multiply_by_quantized_multiplier = tmp_golden;
            end
        end
    end
endfunction


//----------------------------------------------
// 15) Compute Convolution: 
//     - 同時紀錄 sum_before_requant、expected_output
//----------------------------------------------
task compute_convolution;
begin
    reg signed [4*C_AXIS_MDATA_WIDTH-1:0] sum;
    reg signed [31:0] tmp_result;
    integer out_rows, out_cols;
    integer idx;

    out_rows = (img_row - ker_row + 1);
    out_cols = (img_col - ker_col + 1);

    for (i = 0; i < out_rows; i = i + 1) begin
        for (j = 0; j < out_cols; j = j + 1) begin
            sum = 0;
            // 卷積 (MAC 累加)
            for (m = 0; m < ker_row; m = m + 1) begin
                for (n = 0; n < ker_col; n = n + 1) begin
                    sum = sum + img_buffer[(i + m) * img_col + (j + n)] *
                                  weight_buffer[m * ker_col + n];
                end
            end
            idx = i * out_cols + j;
            // [A] 紀錄「requant前」的 sum
            sum_before_requant[idx] = sum;
            // [B] 透過 tb_do_requant計算 "expected_output"
            tmp_result = golden_multiply_by_quantized_multiplier(sum, test_q_multiplier, test_shift);
            expected_output[idx] = (tmp_result > 127)? $signed(POS_127):
                         (tmp_result < -128)? $signed(NEG_128): tmp_result;
            // expected_output[idx]    = tmp_result;
        end
    end
end
endtask

//----------------------------------------------
// 16) Compute dequant and exp: 
//     - Dequant => exp_pipeline => feed pipeline
//----------------------------------------------

wire output_valid_exp;
reg input_valid_exp;
reg signed [31:0] dequant_val;
wire signed [31:0] exp_x;
task compute_exp_after_requant;
    integer idx;
    integer total_elements;
    reg signed [31:0] requant_minus_zero_point;
begin
    total_elements = (img_row - ker_row + 1) * (img_col - ker_col + 1);

    for(idx = 0; idx < total_elements; idx = idx + 1) begin
        // [A] Dequant
        $display("idx = %d, original_requant_data = %d", idx, expected_output[idx]);
        requant_minus_zero_point = expected_output[idx] - input_zero_point;
        $display("requant_minus_zero_point = %d", requant_minus_zero_point);
        if(requant_minus_zero_point >= $signed(input_range_radius)) begin
            exp_output[idx] = $signed(POS_127);
            $display("idx = %d, requant_minus_zero_point = %d in  1", idx,requant_minus_zero_point);
        end else if(requant_minus_zero_point <= $signed(-input_range_radius)) begin
            exp_output[idx] = $signed(NEG_128);
            $display("idx = %d, requant_minus_zero_point = %d in 2",idx,requant_minus_zero_point);
        end else begin
            dequant_val = golden_multiply_by_quantized_multiplier(requant_minus_zero_point, 
                            input_multiplier, input_left_shift);
            $display("dequant_val = %h", dequant_val);
            // [B] exp_pipeline
            @(negedge s00_axis_aclk);
            input_valid_exp = 1;
            @(negedge s00_axis_aclk);
            input_valid_exp = 0;

            wait(output_valid_exp);
            $display("exp_x = %h", exp_x);
            exp_output[idx] = exp_x;
        end

    end

end
endtask

// Instantiate exp_pipeline module
exp_pipeline exp_inst(
    .clk(s00_axis_aclk),
    .rst(s00_axis_aresetn),
    .x(dequant_val),
    .integer_bits(4'd4),  // Q4.27 format
    .input_valid(input_valid_exp),
    .exp_x(exp_x),
    .output_valid(output_valid_exp)
);

//----------------------------------------------
// 17) Check output & Compare
//     - 一併印出 "requant前的值", "expected", "got"
//----------------------------------------------
task check_output;
    integer total_elements;
    integer idx;                // 用於指示期望輸出數組的索引
    integer byte_idx;           // 用於遍歷每個位元組
    reg [63:0] received_data;   // 用於儲存當前周期接收到的64位數據
    reg [7:0]  received_strb;   // 用於儲存位元組使能信號
    reg [7:0]  received_byte;   // 臨時儲存提取的有效位元組
begin
    total_elements = (img_row - ker_row + 1) * (img_col - ker_col + 1);
    idx = 0;
    
    @(negedge m00_axis_aclk);
    m00_axis_tready = 1;
    
    // 等待第一個有效輸出
    wait(m00_axis_tvalid);

    while (m00_axis_tvalid && idx < total_elements) begin
        @(posedge m00_axis_aclk);
        
        if (m00_axis_tdata !== exp_output[idx][7:0]) begin
            $display("Mismatch at element %d: expected=%h, got=%h", 
                        idx, exp_output[idx][7:0], m00_axis_tdata);
            $finish;
        end else begin
            $display("Match at element %d", idx);
        end
        
        idx = idx + 1; // 每處理一個有效位元組，移動到下一個預期元素

        
        // 等待下一個數據周期
        // 如果需要處理 m00_axis_tvalid 的變化，可在此加入額外邏輯
    end

    if(idx < total_elements) begin
        $display("Error: fewer outputs received than expected. Received: %d, Expected: %d", idx, total_elements);
        $finish;
    end
end
endtask

//----------------------------------------------
// 18) (Optional) check_sram_data ...
//----------------------------------------------
//   (此處省略，如原程式需要可保留)

//----------------------------------------------
// 19) 主控 Flow
//----------------------------------------------
initial
begin
    wait(s00_axis_aresetn && m00_axis_aresetn);
    @(posedge s00_axis_aclk);
    $display("start tb_npu3!!!!!!");
    
    compute_convolution(); // 同時產生 sum_before_requant[] & expected_output[]
    compute_exp_after_requant(); // 產生 exp_output[]

    send_image();
    send_weight();

    wait(m00_axis_tvalid);
    check_output(); // Compare & print requant前/後

    // Print out ASCII art
    $display("%s", "                                                                      :+**************-.            ");
    $display("%s", "                                                                     :+****************.            ");
    $display("%s", "                                                                     :+*****++++*******.            ");
    $display("%s", "                                                                     :+*****:.-..=*****.            ");
    $display("%s", "                                                                     :+*****:.-:.=*****.            ");
    $display("%s", "                                                                     :+*****::++*******.            ");
    $display("%s", "                                                                     :+*****--*********.            ");
    $display("%s", "                                     ..                   .=*+.      :+****************.            ");
    $display("%s", "                         .:--.     :*##*:                .*###++=.   :+****************.            ");
    $display("%s", "          .+##*-.       .+####+.  :#####-     .=###-. :*#########+.  :+***+=-::::-++***.            ");
    $display("%s", "         .*#####:        +#####+..*#####-     .=####=.*#########++*###*+:.                          ");
    $display("%s", "         .######:        :######:.*####*:     .:####+..::-###############*.                         ");
    $display("%s", "         .+#####-        .+#####-.=####*:      .+###*.  .-#####*+-:::=####+.                        ");
    $display("%s", "          -#####+.       .+#####: :#####-       =###*...+#####-      .=###*.                        ");
    $display("%s", "          .*#####:        :*##+:. .+#####-.     .+*=..:*######-  ... .+###+.                        ");
    $display("%s", "           :######:.       ...     .*#####+.          -#######::*########*:.                        ");
    $display("%s", "           .:######+.               .*#####-          ...-###*:###*-####*.                          ");
    $display("%s", "            .-######*.               .:*#*=.            .-###+.:*#########:.                        ");
    $display("%s", "              :*####*.                   .......         .++-.  .... .=###=.                        ");
    $display("%s", "               .:==-..              .:+#%#***##%#=.                  ..:..                         ");
    $display("%s", "                                .-*#+-............:+#*-.               ..:..                        ");
    $display("%s", "           .....    ..-*##*=..:#%=....................-%#::*%%%*.. ...:..                          ");
    $display("%s", "            ..::.   =#-....:#%=.........................:##.....:**.....                            ");
    $display("%s", "               .:. :#.....:%+.....................................#- ....:..                        ");
    $display("%s", "           ......  =*.............................................*= .......                        ");
    $display("%s", "           ....:.. .#=...........................................-#:                                ");
    $display("%s", "                    .*%=#-....................................:%@*.  .:....                         ");
    $display("%s", "                 ..   :#-.........................--............*=    ...::.                        ");
    $display("%s", "            ...::... :%-........-%@%:...-+***+-..-%@%:..........-#:                                 ");
    $display("%s", "            ....    .#+..........:...=%#::=+-.-#%:...............**.                                ");
    $display("%s", "                    -#.............=%=.-%@@%=....*+..............:%##:                             ");
    $display("%s", "              .=%##:*=...........-%+.....=#.....-=*#.............=#:.++                             ");
    $display("%s", "              =*..=@#:..........-%:=@#=::-#::=*%%@*=#............=#:.#%%+.                         ");
    $display("%s", "             .*+..=@*...........*=:%%+---==---=##-..**............%-#+...*+.                        ");
    $display("%s", "           .+%#@#*-%*...........#=....-*#%%%#++:.....-@:..........:%:-%-..*+.                        ");
    $display("%s", "           -%:...-#:#-..........*+......==-:-*#.....+#...........:%:.##..++.                        ");
    $display("%s", "           -%:...=%:++..........:#*:.....:-=:.....:*#.............#=.+#+=*+.                        ");
    $display("%s", "           .#=...:#-++............:=#%@@%%%%%#%*=...............#=.=+*%=.                         ");
    $display("%s", "            .**=+#+.*%-.........................................=%-.#+..                            ");
    $display("%s", "              ...#=...+%#+=..................................-%#-.-#-                               ");
    $display("%s", "                 .=%+............................................**.                                ");
    $display("%s", "                    .=*#*.....................................:#*:                                  ");
    $display("%s", "                      .=%.....................................:%:                                   ");
    $display("%s", "                      .:-......................................-.                                   ");
    $display("total_cycles : %d", cycle_count);
    $finish;
end

endmodule
