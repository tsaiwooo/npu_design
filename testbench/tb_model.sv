// ************************************************
// model simaltion for NPU
// ************************************************
`timescale 1ns / 1ps
`include "params.vh"

module tb_model();

typedef struct {
  // op相關（以字串或bit vector儲存皆可，這裡以 bit vector 為例）
  bit [15:0] op;
  // weight相關
  int weight_num;
  int store_sram_idx;
  int op0_weight_idx[2]; // 假設op0需要2個權重索引
  int op1_weight_idx0;
  int op2_weight_idx0;
  int op3_weight_idx0;
  int op0_broadcast;
  int op1_broadcast;
  int op2_broadcast;
  int op3_broadcast;
  int op0_data_counts;
  int op1_data_counts;
  int op2_data_counts;
  int op3_data_counts;

  // Convolution signals
  int batch;
  int img_row;
  int img_col;
  int in_channel; // 輸入 channel
  int out_channel; // 輸出 channel（kernel 的第一個維度）
  int ker_row;
  int ker_col;
  int stride_h;
  int stride_w;
  bit padding;
  int conv_requant_multiplier;
  int conv_requant_shift;
  int conv_requant_output_offset;

  // Exp signals
  int exp_deq_input_range_radius;
  int exp_deq_input_zero_point;
  int exp_deq_input_multiplier;
  int exp_deq_input_left_shift;
  int exp_req_input_quantized_multiplier;
  int exp_req_input_shift;
  int exp_req_input_offset;

  // Reciprocal signals
  int reciprocal_deq_input_zero_point;
  int reciprocal_deq_input_range_radius;
  int reciprocal_deq_input_multiplier;
  int reciprocal_deq_input_left_shift;
  int reciprocal_req_input_quantized_multiplier;
  int reciprocal_req_input_shift;
  int reciprocal_req_input_offset;

  // ADD signals
  int add_input1_offset;
  int add_input2_offset;
  int add_left_shift;
  int add_input1_multiplier;
  int add_input2_multiplier;
  int add_input1_shift;
  int add_input2_shift;
  int add_output_multiplier;
  int add_output_shift;
  int add_output_offset;
  int add_quantized_activation_min;
  int add_quantized_activation_max;

  // SUB signals
  int sub_input1_offset;
  int sub_input2_offset;
  int sub_left_shift;
  int sub_input1_multiplier;
  int sub_input2_multiplier;
  int sub_input1_shift;
  int sub_input2_shift;
  int sub_output_multiplier;
  int sub_output_shift;
  int sub_output_offset;
  int sub_quantized_activation_min;
  int sub_quantized_activation_max;

  // MUL signals
  int mul_input1_offset;
  int mul_input2_offset;
  int mul_output_multiplier;
  int mul_output_shift;
  int mul_output_offset;
  int mul_quantized_activation_min;
  int mul_quantized_activation_max;

  // op weight & data counts that store in buffer
  int op0_input_data_total_counts;
  int op0_weight_total_counts;
  int op1_weight_total_counts;
  int op2_weight_total_counts;
  int op3_weight_total_counts;
} metadata_t;
metadata_t metadata[0:9999];
int num_ops = 0;

// READ metadata function, support function
function string read_next_line(int file);
  string line;
  int r;
  begin
    line = "";
    while (1) begin
      r = $fgets(line, file);
      if (r == 0) begin
         return ""; // EOF
      end
    //   line = line.tolower().trim();
      if (line.len() == 0) continue;
      if (line[0] == "#") continue;
      if (line[0] == "\n" || line[0] == "\r") continue;
      return line;
    end
  end
endfunction

function string remove_newline(string in_line);
  string out_line;
  int i;
  out_line = "";
  for (i = 0; i < in_line.len(); i = i + 1) begin
    if ((in_line[i] != "\n") && (in_line[i] != "\r"))
      out_line = {out_line, in_line[i]};
  end
  return out_line;
endfunction

// Task: 依序讀取 metadata，直到讀到 "1234567890"
task read_metadata(ref metadata_t meta_array[0:9999], output int meta_count);
  int file;
  string line;
  int r;
  int i;
  metadata_t tmp;
  reg [3:0] op[0:3];
  reg [8*16-1:0] tok; 
  meta_count = 0;
  file = $fopen("metadata.txt", "r");
  if (file == 0) begin
    $display("Error: Unable to open metadata.txt");
    disable read_metadata;
  end

  // 主迴圈：讀取每個 metadata 結構
  while (1) begin
    line = read_next_line(file);
    line = remove_newline(line);
    // 讀取 op 字串
    // if (line == "") break;
    // 若行中包含終止字串 "1234567890" ，則結束
    if (line == "1234567890")
      break;
    // 此行應該是 op，例如 "0000000000110001"
    // 這裡使用 $sscanf 將字串轉成 16 位的 bit vector（格式 "%b"）
    // r = $sscanf(line, "%s",tok);
    // if(tok == "1234567890") break;
    r = $sscanf(line, "%b", tmp.op);
    $display("tok = %s, op = %b",tok, tmp.op);
    op[0] = tmp.op[3:0];
    op[1] = tmp.op[7:4];
    op[2] = tmp.op[11:8];
    op[3] = tmp.op[15:12];
    $display("op0 = %b, op1 = %b, op2 = %b, op3 = %b", op[0], op[1], op[2], op[3]);
    // break;
    // r = $sscanf(line, "%b", tmp.op);
    // if(tmp.op == "1234567890") break;

    // 讀取 weight_num
    line = read_next_line(file);
    r = $sscanf(line, "%d", tmp.weight_num);
    $display("weight_num = %d", tmp.weight_num);
    // 讀取 store_sram_idx 與 op0_weight_idx0、op0_weight_idx1、op1_weight_idx0、op2_weight_idx0、op3_weight_idx0
    line = read_next_line(file);
    // 假設格式為 "2 0 1 0 0 0"
    r = $sscanf(line, "%d %d %d %d %d %d",
                tmp.store_sram_idx,
                tmp.op0_weight_idx[0],
                tmp.op0_weight_idx[1],
                tmp.op1_weight_idx0,
                tmp.op2_weight_idx0,
                tmp.op3_weight_idx0);

    // 讀取 op_broadcasts：op0_broadcast op1_broadcast op2_broadcast op3_broadcast
    line = read_next_line(file);
    r = $sscanf(line, "%d %d %d %d",
                tmp.op0_broadcast,
                tmp.op1_broadcast,
                tmp.op2_broadcast,
                tmp.op3_broadcast);

    // 讀取 op_data_counts：op0_data_counts op1_data_counts op2_data_counts op3_data_counts
    line = read_next_line(file);
    r = $sscanf(line, "%d %d %d %d",
                tmp.op0_data_counts,
                tmp.op1_data_counts,
                tmp.op2_data_counts,
                tmp.op3_data_counts);
    // 讀取 op0_input_data_total_counts, op0_weight_total_counts, op1_weight_total_counts, op2_weight_total_counts, op3_weight_total_counts
    line = read_next_line(file);
    r = $sscanf(line, "%d %d %d %d %d",
                tmp.op0_input_data_total_counts,
                tmp.op0_weight_total_counts,
                tmp.op1_weight_total_counts,
                tmp.op2_weight_total_counts,
                tmp.op3_weight_total_counts);

    // 讀取 convolution signals：
    // 讀取 stride_h, stride_w, padding
    i = 0;
    while(i<4 && op[i] != 4'b0000) begin
        // if(op[i] == 4'b0000) break;
        line = read_next_line(file);
        case(op[i])
            4'b0001: begin // conv
                $display("conv, i = %d", i);
                r = $sscanf(line, "%d %d %d", tmp.stride_h, tmp.stride_w, tmp.padding);
                $display("stride_h = %d, stride_w = %d, padding = %b", tmp.stride_h, tmp.stride_w, tmp.padding);
                // 讀取 image size: batch, img_row, img_col, in_channel
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d", tmp.batch, tmp.img_row, tmp.img_col, tmp.in_channel);
                $display("batch = %d, img_row = %d, img_col = %d, in_channel = %d", tmp.batch, tmp.img_row, tmp.img_col, tmp.in_channel);
                // 讀取 kernel size: out_channel, ker_row, ker_col
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d", tmp.out_channel, tmp.ker_row, tmp.ker_col);
                $display("out_channel = %d, ker_row = %d, ker_col = %d", tmp.out_channel, tmp.ker_row, tmp.ker_col);
                // 讀取 conv requant: conv_requant_multiplier, conv_requant_shift
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d", tmp.conv_requant_multiplier, tmp.conv_requant_shift,tmp.conv_requant_output_offset);
                $display("conv requant: conv_requant_multiplier = %d, conv_requant_shift = %d, conv_requant_output_offset = %d", tmp.conv_requant_multiplier, tmp.conv_requant_shift,tmp.conv_requant_output_offset);
            end
            4'b0010: begin // FC
                $display("FC , i = %d", i);
                r = $sscanf(line, "%d %d %d", tmp.stride_h, tmp.stride_w, tmp.padding);

                // 讀取 image size: batch, img_row, img_col, in_channel
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d", tmp.batch, tmp.img_row, tmp.img_col, tmp.in_channel);

                // 讀取 kernel size: out_channel, ker_row, ker_col
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d", tmp.out_channel, tmp.ker_row, tmp.ker_col);

                // 讀取 conv requant: conv_requant_multiplier, conv_requant_shift
                line = read_next_line(file);
                r = $sscanf(line, "%d %d %d", tmp.conv_requant_multiplier, tmp.conv_requant_shift,tmp.conv_requant_output_offset);
            end
            4'b0011: begin // Exp
                $display("Exp , i = %d", i);
                // 讀取 exp signals: exp_deq_input_range_radius, exp_deq_input_zero_point, exp_deq_input_multiplier, exp_deq_input_left_shift, exp_req_input_quantized_multiplier, exp_req_input_shift
                // line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d %d %d %d", tmp.exp_deq_input_range_radius,
                            tmp.exp_deq_input_zero_point, tmp.exp_deq_input_multiplier, tmp.exp_deq_input_left_shift, tmp.exp_req_input_quantized_multiplier, tmp.exp_req_input_shift, tmp.exp_req_input_offset);
            end
            4'b0100: begin // Reciprocal
                $display("Reciprocal , i = %d", i);
                 // 讀取 reciprocal signals: reciprocal_deq_input_zero_point, reciprocal_deq_input_range_radius, reciprocal_deq_input_multiplier, reciprocal_deq_input_left_shift, reciprocal_req_input_quantized_multiplier, reciprocal_req_input_shift
                // line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d %d %d %d", tmp.reciprocal_deq_input_zero_point,
                            tmp.reciprocal_deq_input_range_radius, tmp.reciprocal_deq_input_multiplier, tmp.reciprocal_deq_input_left_shift, tmp.reciprocal_req_input_quantized_multiplier, tmp.reciprocal_req_input_shift, tmp.reciprocal_req_input_offset);
            end
            4'b0101: begin // ADD
                $display("ADD , i = %d", i);
                // 讀取 ADD signals (12個數字)
                // line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d %d",
                            tmp.add_input1_offset, tmp.add_input2_offset,
                            tmp.add_left_shift,
                            tmp.add_input1_multiplier, tmp.add_input2_multiplier,
                            tmp.add_input1_shift, tmp.add_input2_shift,
                            tmp.add_output_multiplier, tmp.add_output_shift,
                            tmp.add_output_offset,
                            tmp.add_quantized_activation_min, tmp.add_quantized_activation_max);
            end
            4'b0110: begin // SUB
                $display("SUB , i = %d", i);
                // 讀取 SUB signals (12個數字)
                // line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d %d",
                            tmp.sub_input1_offset, tmp.sub_input2_offset,
                            tmp.sub_left_shift,
                            tmp.sub_input1_multiplier, tmp.sub_input2_multiplier,
                            tmp.sub_input1_shift, tmp.sub_input2_shift,
                            tmp.sub_output_multiplier, tmp.sub_output_shift,
                            tmp.sub_output_offset,
                            tmp.sub_quantized_activation_min, tmp.sub_quantized_activation_max);
            end
            4'b0111: begin // MUL
                $display("MUL, i = %d", i);
                // 讀取 MUL signals (7個數字)
                // line = read_next_line(file);
                r = $sscanf(line, "%d %d %d %d %d %d %d",
                            tmp.mul_input1_offset, tmp.mul_input2_offset,
                            tmp.mul_output_multiplier, tmp.mul_output_shift,
                            tmp.mul_output_offset,
                            tmp.mul_quantized_activation_min, tmp.mul_quantized_activation_max);
            end
        endcase
        i = i+1;
    end
    // r = $sscanf(line, "%d %d %d", tmp.stride_h, tmp.stride_w, tmp.padding);

    // // 讀取 image size: batch, img_row, img_col, in_channel
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d", tmp.batch, tmp.img_row, tmp.img_col, tmp.in_channel);

    // // 讀取 kernel size: out_channel, ker_row, ker_col
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d", tmp.out_channel, tmp.ker_row, tmp.ker_col);

    // // 讀取 conv requant: conv_requant_multiplier, conv_requant_shift
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d", tmp.conv_requant_multiplier, tmp.conv_requant_shift,tmp.conv_requant_output_offset);

    // // 讀取 exp signals: exp_deq_input_range_radius, exp_deq_input_zero_point, exp_deq_input_multiplier, exp_deq_input_left_shift, exp_req_input_quantized_multiplier, exp_req_input_shift
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d %d %d %d", tmp.exp_deq_input_range_radius,
    //             tmp.exp_deq_input_zero_point, tmp.exp_deq_input_multiplier, tmp.exp_deq_input_left_shift, tmp.exp_req_input_quantized_multiplier, tmp.exp_req_input_shift, tmp.exp_req_input_offset);

    // // 讀取 reciprocal signals: reciprocal_deq_input_zero_point, reciprocal_deq_input_range_radius, reciprocal_deq_input_multiplier, reciprocal_deq_input_left_shift, reciprocal_req_input_quantized_multiplier, reciprocal_req_input_shift
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d %d %d %d", tmp.reciprocal_deq_input_zero_point,
    //             tmp.reciprocal_deq_input_range_radius, tmp.reciprocal_deq_input_multiplier, tmp.reciprocal_deq_input_left_shift, tmp.reciprocal_req_input_quantized_multiplier, tmp.reciprocal_req_input_shift, tmp.reciprocal_req_input_offset);
    // // 讀取 ADD signals (12個數字)
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d %d",
    //             tmp.add_input1_offset, tmp.add_input2_offset,
    //             tmp.add_left_shift,
    //             tmp.add_input1_multiplier, tmp.add_input2_multiplier,
    //             tmp.add_input1_shift, tmp.add_input2_shift,
    //             tmp.add_output_multiplier, tmp.add_output_shift,
    //             tmp.add_output_offset,
    //             tmp.add_quantized_activation_min, tmp.add_quantized_activation_max);

    // // 讀取 SUB signals (12個數字)
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d %d",
    //             tmp.sub_input1_offset, tmp.sub_input2_offset,
    //             tmp.sub_left_shift,
    //             tmp.sub_input1_multiplier, tmp.sub_input2_multiplier,
    //             tmp.sub_input1_shift, tmp.sub_input2_shift,
    //             tmp.sub_output_multiplier, tmp.sub_output_shift,
    //             tmp.sub_output_offset,
    //             tmp.sub_quantized_activation_min, tmp.sub_quantized_activation_max);

    // // 讀取 MUL signals (7個數字)
    // // line = read_next_line(file);
    // r = $sscanf(line, "%d %d %d %d %d %d %d",
    //             tmp.mul_input1_offset, tmp.mul_input2_offset,
    //             tmp.mul_output_multiplier, tmp.mul_output_shift,
    //             tmp.mul_output_offset,
    //             tmp.mul_quantized_activation_min, tmp.mul_quantized_activation_max);

    // 印出所有讀取到的資料
    $display("------------------------------------------------------");
    $display("Metadata[%0d]:", meta_count);
    $display("  op = %b", tmp.op);
    $display("  weight_num = %0d, store_sram_idx = %0d", tmp.weight_num, tmp.store_sram_idx);
    $display("  op0_weight_idx = {%0d, %0d}", tmp.op0_weight_idx[0], tmp.op0_weight_idx[1]);
    $display("  op1_weight_idx0 = %0d, op2_weight_idx0 = %0d, op3_weight_idx0 = %0d",
             tmp.op1_weight_idx0, tmp.op2_weight_idx0, tmp.op3_weight_idx0);
    $display("  op broadcasts = %0d, %0d, %0d, %0d",
             tmp.op0_broadcast, tmp.op1_broadcast, tmp.op2_broadcast, tmp.op3_broadcast);
    $display("  op data counts = %0d, %0d, %0d, %0d",
             tmp.op0_data_counts, tmp.op1_data_counts, tmp.op2_data_counts, tmp.op3_data_counts);
    $display("  Convolution: batch = %0d, img_row = %0d, img_col = %0d, in_channel = %0d, out_channel = %0d",
             tmp.batch, tmp.img_row, tmp.img_col, tmp.in_channel, tmp.out_channel);
    $display("  Kernel: ker_row = %0d, ker_col = %0d, stride = (%0d, %0d), padding = %b",
             tmp.ker_row, tmp.ker_col, tmp.stride_h, tmp.stride_w, tmp.padding);
    $display("  Conv requant: multiplier = %0d, shift = %0d",
             tmp.conv_requant_multiplier, tmp.conv_requant_shift);
    $display("  Exp signals: deq_range = %0d, deq_zero = %0d, deq_multiplier = %0d, deq_left_shift = %0d, req_multiplier = %0d, req_shift = %0d",
             tmp.exp_deq_input_range_radius, tmp.exp_deq_input_zero_point, tmp.exp_deq_input_multiplier, tmp.exp_deq_input_left_shift, tmp.exp_req_input_quantized_multiplier, tmp.exp_req_input_shift);
    $display("  Reciprocal signals: deq_zero = %0d, deq_range = %0d, deq_multiplier = %0d, deq_left_shift = %0d, req_multiplier = %0d, req_shift = %0d",
             tmp.reciprocal_deq_input_zero_point, tmp.reciprocal_deq_input_range_radius, tmp.reciprocal_deq_input_multiplier, tmp.reciprocal_deq_input_left_shift, tmp.reciprocal_req_input_quantized_multiplier, tmp.reciprocal_req_input_shift);
    $display("  ADD signals: offsets = (%0d, %0d), left_shift = %0d, multipliers = (%0d, %0d), shifts = (%0d, %0d), output = (mult=%0d, shift=%0d, offset=%0d), activation = (%0d, %0d)",
             tmp.add_input1_offset, tmp.add_input2_offset, tmp.add_left_shift, tmp.add_input1_multiplier, tmp.add_input2_multiplier,
             tmp.add_input1_shift, tmp.add_input2_shift, tmp.add_output_multiplier, tmp.add_output_shift, tmp.add_output_offset,
             tmp.add_quantized_activation_min, tmp.add_quantized_activation_max);
    $display("  SUB signals: offsets = (%0d, %0d), left_shift = %0d, multipliers = (%0d, %0d), shifts = (%0d, %0d), output = (mult=%0d, shift=%0d, offset=%0d), activation = (%0d, %0d)",
             tmp.sub_input1_offset, tmp.sub_input2_offset, tmp.sub_left_shift, tmp.sub_input1_multiplier, tmp.sub_input2_multiplier,
             tmp.sub_input1_shift, tmp.sub_input2_shift, tmp.sub_output_multiplier, tmp.sub_output_shift, tmp.sub_output_offset,
             tmp.sub_quantized_activation_min, tmp.sub_quantized_activation_max);
    $display("  MUL signals: offsets = (%0d, %0d), output = (mult=%0d, shift=%0d, offset=%0d), activation = (%0d, %0d)",
             tmp.mul_input1_offset, tmp.mul_input2_offset, tmp.mul_output_multiplier, tmp.mul_output_shift, tmp.mul_output_offset,
             tmp.mul_quantized_activation_min, tmp.mul_quantized_activation_max);
    $display("------------------------------------------------------");
    // 將該筆 metadata 儲存到陣列中
    meta_array[meta_count] = tmp;
    meta_count++;
    // if(meta_count == 3 ) $finish;
    // 接下來讀取一個分隔線（如果有），並繼續下一筆
    // 讀取分隔線（如果存在）：
    // line = read_next_line(file);
    // line = remove_newline(line);
    // 若讀到 "1234567890" 則跳出
    // if (line == "1234567890")
    //   break;
  end

  $fclose(file);
  $display("Read %0d metadata entries", meta_count);
endtask

//----------------------------------------------
// 1) Parameters
//----------------------------------------------
parameter PERIOD              = 10;
parameter MAX_MACS            = 64;
parameter ADDR_WIDTH          = 13;
parameter C_AXIS_TDATA_WIDTH  = 64;
parameter C_AXIS_MDATA_WIDTH  = 64;
parameter MAX_CHANNELS        = 64;
parameter NUM_CHANNELS_WIDTH  = $clog2(MAX_CHANNELS+1);
parameter MAX_VECTOR_SIZE     = 8;
localparam signed [7:0] NEG_128 = -128;
localparam signed [7:0] POS_127 =  127;

// TB 裡用到: SHIFT 的常數
localparam signed NEG_12 = -12;

//----------------------------------------------
// 2) Variables
//----------------------------------------------
integer img_file, weight_file, scan_result;
integer b, i, j, m, n, oc,ic;

//----------------------------------------------
// 3) Buffers and arrays
//----------------------------------------------

// (A) 存放 image / weight
reg signed [C_AXIS_TDATA_WIDTH-1:0] img_buffer    [0:2**18-1];
reg signed [C_AXIS_TDATA_WIDTH-1:0] weight_buffer [0:2**ADDR_WIDTH-1];

// (B) 新增：保存「卷積尚未 Requant」(累加) 與「Requant 後」的預期值
reg signed [31:0] sum_before_requant [0:2**18-1];  // Requant 前的累加
reg signed [C_AXIS_MDATA_WIDTH-1:0] expected_output [0:2**18-1]; // Requant 後的結果
reg signed [31:0] exp_output [0:2**18-1]; // dequant+exp 後的結果

//----------------------------------------------
// 4) Inputs to NPU
//----------------------------------------------
reg   s00_axis_aclk    = 1'b0;
reg   s00_axis_aresetn = 1;
reg   [C_AXIS_TDATA_WIDTH-1:0] s00_axis_tdata = 0;
reg   s00_axis_tvalid  = 0;
reg   s00_axis_tlast   = 0;
reg   [4*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser = 0;
reg   m00_axis_aclk    = 1'b0;
reg   m00_axis_aresetn = 1;
reg   m00_axis_tready  = 0;
// ------------------------------------------------
// exp 參數
// ------------------------------------------------
reg   [31:0]        exp_deq_input_range_radius = 480;
reg   signed [31:0] exp_deq_input_zero_point = -3;
reg   signed [31:0] exp_deq_input_left_shift = 22;
reg   signed [31:0] exp_deq_input_multiplier = 1591541760;
reg   [31:0]        exp_req_input_quantized_multiplier = 0;
reg   signed [31:0] exp_req_input_shift = 0;
reg   signed [31:0] exp_req_input_offset = 0;

// -----------------------------------------------
// reciprocal 參數
// -----------------------------------------------
reg signed [31:0]        reciprocal_deq_input_zero_point = 0;
reg signed [31:0]        reciprocal_deq_input_range_radius = 0;
reg signed [31:0]        reciprocal_deq_input_left_shift = 0;
reg  [31:0]        reciprocal_deq_input_multiplier = 0;
reg  [31:0]        reciprocal_req_input_quantized_multiplier = 0;
reg signed [31:0]        reciprocal_req_input_shift = 0;
reg signed [31:0]        reciprocal_req_input_offset = 0;


//----------------------------------------------
// Convolution 參數
//----------------------------------------------
reg [ADDR_WIDTH-1:0] batch;
reg [ADDR_WIDTH-1:0] img_row, img_col;
reg [ADDR_WIDTH-1:0] ker_row, ker_col;
reg [3:0]            stride_h, stride_w;
reg [ADDR_WIDTH-1:0] in_channel, out_channel;
reg                  padding;

//----------------------------------------------
// MUL, ADD, SUB, Requant/Dequant 參數
//----------------------------------------------
reg signed [INT32_SIZE-1:0] mul_input1_offset, mul_input2_offset;
reg signed [INT32_SIZE-1:0] mul_output_multiplier, mul_output_shift, mul_output_offset;
reg signed [31:0]           mul_quantized_activation_min, mul_quantized_activation_max;

reg signed [INT32_SIZE-1:0] add_input1_offset, add_input2_offset;
reg signed [INT32_SIZE-1:0] add_left_shift;
reg signed [INT32_SIZE-1:0] add_input1_multiplier, add_input2_multiplier;
reg signed [INT32_SIZE-1:0] add_input1_shift, add_input2_shift;
reg signed [INT32_SIZE-1:0] add_output_multiplier, add_output_shift, add_output_offset;
reg signed [31:0]           add_quantized_activation_min, add_quantized_activation_max;

reg signed [INT32_SIZE-1:0] sub_input1_offset, sub_input2_offset;
reg signed [INT32_SIZE-1:0] sub_left_shift;
reg signed [INT32_SIZE-1:0] sub_input1_multiplier, sub_input2_multiplier;
reg signed [INT32_SIZE-1:0] sub_input1_shift, sub_input2_shift;
reg signed [INT32_SIZE-1:0] sub_output_multiplier, sub_output_shift, sub_output_offset;
reg signed [31:0]           sub_quantized_activation_min, sub_quantized_activation_max;

// reg signed [31:0] exp_deq_input_zero_point, exp_deq_input_range_radius, exp_deq_input_left_shift, exp_deq_input_multiplier;
// ------------------------------------------------
// metadata that control the operation
// ------------------------------------------------
reg metadata_valid_i; // metadata valid signal
reg metadata_done; // metadata done signal which means the metadata is valid and NPU goto next state
reg finish_calc; // the whole model finish signal
reg [15:0] op; // each operation which 4bits is a operation and 4 operations in total
reg [2:0] weight_num; // how many weights are used in the operation
reg [2:0] store_sram_idx0; // which sram index to store the data
reg [2:0] op0_weight_sram_idx0, op0_weight_sram_idx1, op1_weight_sram_idx0, op2_weight_sram_idx0, op3_weight_sram_idx0; // each opearation's weight and data sram index
reg [2:0] op0_broadcast, op1_broadcast, op2_broadcast, op3_broadcast; // each operation's broadcast signal, 1 means broadcast
reg [MAX_ADDR_WIDTH-1:0] op0_data_counts, op1_data_counts, op2_data_counts, op3_data_counts; // each operation's total output data counts
reg [31:0] op0_input_data_total_counts,op0_weight_total_counts, op1_weight_total_counts, op2_weight_total_counts, op3_weight_total_counts;


//----------------------------------------------
// 5) Requant 參數 (TB 中固定值) for convolution output
//----------------------------------------------
// reg [31:0]  test_q_multiplier = 32'd1388164317; 
// reg signed [31:0] test_shift  = -9;
reg [31:0]  test_q_multiplier;
reg signed [31:0] test_shift;
reg signed [31:0] test_output_offset;


//----------------------------------------------
// 6) Outputs from NPU
//----------------------------------------------
wire  s00_axis_tready;
wire  signed [C_AXIS_MDATA_WIDTH-1:0] m00_axis_tdata;
// wire [7:0]  m00_axis_tstrb;
wire  m00_axis_tvalid;
wire  m00_axis_tlast;
wire  [NUM_CHANNELS_WIDTH-1:0] m00_axis_tuser;
wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0] dump; // unused
wire [63:0] cycle_count,sram_access_counts,dram_access_counts,elementwise_idle_counts;

// ------------------------------------------------
// metadata from NPU
// ------------------------------------------------
wire layer_calc_done;

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
    $fsdbDumpvars(0, tb_model.u_npu, "+all");
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
wire [(C_AXIS_MDATA_WIDTH/8)-1:0] dummy_m00_tstrb;
npu #(
    .MAX_MACS(MAX_MACS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .C_AXIS_TDATA_WIDTH(C_AXIS_TDATA_WIDTH),
    .C_AXIS_MDATA_WIDTH(C_AXIS_MDATA_WIDTH),
    .MAX_CHANNELS(MAX_CHANNELS),
    .NUM_CHANNELS_WIDTH(NUM_CHANNELS_WIDTH),
    .MAX_VECTOR_SIZE(MAX_VECTOR_SIZE)
) u_npu (
    .s00_axis_aclk(s00_axis_aclk),
    .s00_axis_aresetn(s00_axis_aresetn),
    .s00_axis_tdata(s00_axis_tdata),
    .s00_axis_tvalid(s00_axis_tvalid),
    .s00_axis_tready(s00_axis_tready),
    .s00_axis_tlast(s00_axis_tlast),
    .s00_axis_tuser(s00_axis_tuser),
    .s00_axis_tstrb(8'b0),
    .m00_axis_aclk(m00_axis_aclk),
    .m00_axis_aresetn(m00_axis_aresetn),
    .m00_axis_tdata(m00_axis_tdata),
    .m00_axis_tstrb(dummy_m00_tstrb),
    .m00_axis_tvalid(m00_axis_tvalid),
    .m00_axis_tready(m00_axis_tready),
    .m00_axis_tlast(m00_axis_tlast),
    .m00_axis_tuser(m00_axis_tuser),
    
    .batch(batch),
    .img_row(img_row),
    .img_col(img_col),
    .ker_row(ker_row),
    .ker_col(ker_col),
    .stride_h(stride_h),
    .stride_w(stride_w),
    .in_channel(in_channel),
    .out_channel(out_channel),
    .padding(padding),
    
    .mul_input1_offset(mul_input1_offset),
    .mul_input2_offset(mul_input2_offset),
    .mul_output_multiplier(mul_output_multiplier),
    .mul_output_shift(mul_output_shift),
    .mul_output_offset(mul_output_offset),
    .mul_quantized_activation_min(mul_quantized_activation_min),
    .mul_quantized_activation_max(mul_quantized_activation_max),
    
    .add_input1_offset(add_input1_offset),
    .add_input2_offset(add_input2_offset),
    .add_left_shift(add_left_shift),
    .add_input1_multiplier(add_input1_multiplier),
    .add_input2_multiplier(add_input2_multiplier),
    .add_input1_shift(add_input1_shift),
    .add_input2_shift(add_input2_shift),
    .add_output_multiplier(add_output_multiplier),
    .add_output_shift(add_output_shift),
    .add_output_offset(add_output_offset),
    .add_quantized_activation_min(add_quantized_activation_min),
    .add_quantized_activation_max(add_quantized_activation_max),
    
    .sub_input1_offset(sub_input1_offset),
    .sub_input2_offset(sub_input2_offset),
    .sub_left_shift(sub_left_shift),
    .sub_input1_multiplier(sub_input1_multiplier),
    .sub_input2_multiplier(sub_input2_multiplier),
    .sub_input1_shift(sub_input1_shift),
    .sub_input2_shift(sub_input2_shift),
    .sub_output_multiplier(sub_output_multiplier),
    .sub_output_shift(sub_output_shift),
    .sub_output_offset(sub_output_offset),
    .sub_quantized_activation_min(sub_quantized_activation_min),
    .sub_quantized_activation_max(sub_quantized_activation_max),
    
    .quantized_multiplier(test_q_multiplier),
    .shift(test_shift),
    .gemm_output_offset(test_output_offset),
    
    .exp_deq_input_zero_point(exp_deq_input_zero_point),
    .exp_deq_input_range_radius(exp_deq_input_range_radius),
    .exp_deq_input_left_shift(exp_deq_input_left_shift),
    .exp_deq_input_multiplier(exp_deq_input_multiplier),
    .exp_req_input_quantized_multiplier(exp_req_input_quantized_multiplier),
    .exp_req_input_shift(exp_req_input_shift),
    .exp_req_input_offset(exp_req_input_offset),

    .reciprocal_deq_input_zero_point(reciprocal_deq_input_zero_point),
    .reciprocal_deq_input_range_radius(reciprocal_deq_input_range_radius),
    .reciprocal_deq_input_multiplier(reciprocal_deq_input_multiplier),
    .reciprocal_deq_input_left_shift(reciprocal_deq_input_left_shift),
    .reciprocal_req_input_quantized_multiplier(reciprocal_req_input_quantized_multiplier),
    .reciprocal_req_input_shift(reciprocal_req_input_shift),
    .reciprocal_req_input_offset(reciprocal_req_input_offset),
    
    .metadata_valid_i(metadata_valid_i),
    .finish_calc(finish_calc),
    .op(op),
    .weight_num(weight_num),
    .store_sram_idx0(store_sram_idx0),
    .op0_weight_sram_idx0(op0_weight_sram_idx0),
    .op0_weight_sram_idx1(op0_weight_sram_idx1),
    .op1_weight_sram_idx0(op1_weight_sram_idx0),
    .op2_weight_sram_idx0(op2_weight_sram_idx0),
    .op3_weight_sram_idx0(op3_weight_sram_idx0),
    .op0_broadcast(op0_broadcast),
    .op1_broadcast(op1_broadcast),
    .op2_broadcast(op2_broadcast),
    .op3_broadcast(op3_broadcast),
    .metadata_done(metadata_done),
    
    .op0_data_counts(op0_data_counts),
    .op1_data_counts(op1_data_counts),
    .op2_data_counts(op2_data_counts),
    .op3_data_counts(op3_data_counts),

    .op0_weight_total_counts(op0_weight_total_counts),
    .op1_weight_total_counts(op1_weight_total_counts),
    .op2_weight_total_counts(op2_weight_total_counts),
    .op3_weight_total_counts(op3_weight_total_counts),
    .op0_input_data_total_counts(op0_input_data_total_counts),
    
    .cycle_count(cycle_count),
    .sram_access_counts(sram_access_counts),
    .dram_access_counts(dram_access_counts),
    .elementwise_idle_counts(elementwise_idle_counts),
    .layer_calc_done(layer_calc_done)
);

//----------------------------------------------
// 11) Read image / weight data into buffers
//----------------------------------------------
task read_weight;
begin
    img_file = $fopen("image_data.txt", "r");
    weight_file = $fopen("kerenl_data.txt", "r");
    stride_h = 2;
    stride_w = 2;
    padding = 0;
    // 讀取 image row/col
    $display("read_weight -> img_row = %d, img_col = %d, in_channel = %d, total = %d", img_row, img_col, in_channel,batch * img_col * img_row * in_channel);
    // scan_result = $fscanf(img_file, "%d %d %d %d\n", batch , img_row, img_col, in_channel);
    for (i = 0; i < batch * img_col * img_row * in_channel; i = i + 1) begin
        scan_result = $fscanf(img_file, "%d\n", img_buffer[i]);
        $display("img_buffer[%d] = %d", i, img_buffer[i]);
    end
    $display("aaaaaaa");
    // 讀取 weight row/col
    // scan_result = $fscanf(weight_file, "%d %d %d\n", out_channel , ker_row, ker_col);
    $display("read_weight -> ker_row = %d, out_channel = %d, ker_col = %d, in_channel = %d, total = %d", out_channel,ker_row, ker_col, in_channel, out_channel * ker_col * ker_row * in_channel);
    for (i = 0; i < out_channel * ker_col * ker_row * in_channel; i = i + 1) begin
        scan_result = $fscanf(weight_file, "%d\n", weight_buffer[i]);
        $display("weight_buffer[%d] = %d", i, weight_buffer[i]);
    end
    $display("finish");

    $fclose(img_file);
    $fclose(weight_file);
end
endtask

//----------------------------------------------
// 12) 送出 image data
//----------------------------------------------
integer tmp;
task send_image;
    reg [C_AXIS_TDATA_WIDTH-1:0] combined;
    int total;
begin
    $display("img_row = %d, img_col = %d, last = %d", img_row, img_col, img_row * img_col - 1);
    @(posedge s00_axis_aclk);
    total = img_row * img_col * in_channel * batch;
    $display("send_image -> total = %d", total);
    for (i = 0; i < total; i = i + 8) begin
        combined = { ((i+7 < total) ? img_buffer[i+7][7:0] : 8'd0),
             ((i+6 < total) ? img_buffer[i+6][7:0] : 8'd0),
             ((i+5 < total) ? img_buffer[i+5][7:0] : 8'd0),
             ((i+4 < total) ? img_buffer[i+4][7:0] : 8'd0),
             ((i+3 < total) ? img_buffer[i+3][7:0] : 8'd0),
             ((i+2 < total) ? img_buffer[i+2][7:0] : 8'd0),
             ((i+1 < total) ? img_buffer[i+1][7:0] : 8'd0),
             ((i   < total) ? img_buffer[i][7:0]   : 8'd0) };
        s00_axis_tdata  = combined;
        s00_axis_tvalid = 1;
        s00_axis_tlast  = ((i+8) >= total - 1);
        tmp = 1;
        // s00_axis_tuser  = { batch , img_col, img_row, img_in_channel, tmp[NUM_CHANNELS_WIDTH-1:0]};  // metadata in tuser
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
    reg [C_AXIS_TDATA_WIDTH-1:0] combined;
    int total;
begin
    $display("ker_row = %d, ker_col = %d, last = %d", ker_row, ker_col, ker_row * ker_col - 1);
    @(posedge s00_axis_aclk);
    total = out_channel * ker_row * ker_col * in_channel;
    for (i = 0; i < total; i = i + 8) begin
        combined = { ((i+7 < total) ? weight_buffer[i+7][7:0] : 8'd0),
                 ((i+6 < total) ? weight_buffer[i+6][7:0] : 8'd0),
                 ((i+5 < total) ? weight_buffer[i+5][7:0] : 8'd0),
                 ((i+4 < total) ? weight_buffer[i+4][7:0] : 8'd0),
                 ((i+3 < total) ? weight_buffer[i+3][7:0] : 8'd0),
                 ((i+2 < total) ? weight_buffer[i+2][7:0] : 8'd0),
                 ((i+1 < total) ? weight_buffer[i+1][7:0] : 8'd0),
                 ((i   < total) ? weight_buffer[i][7:0]   : 8'd0) };
        s00_axis_tdata  = combined;
        s00_axis_tvalid = 1;
        s00_axis_tlast  = ((i+8) >= total - 1);
        tmp = 1;
        // s00_axis_tuser  = { padding, stride_h , stride_w , ker_row, ker_col, out_channel, tmp[NUM_CHANNELS_WIDTH-1:0]};
        wait(s00_axis_tready);
        @(posedge s00_axis_aclk);
    end
    s00_axis_tvalid = 0;
    s00_axis_tlast  = 0;
end
endtask

task send_weight_data;
  // 輸入參數：
  //   weight_buffer_array：存有權重資料的陣列（每筆資料寬度為 DATA_WIDTH，即 C_AXIS_TDATA_WIDTH）
  //   num_elements：要送出的權重筆數
  input reg [7:0] weight_buffer_array [0:2**MAX_ADDR_WIDTH-1];
  input integer num_elements;
  // 內部變數
  integer idx;
  reg [C_AXIS_TDATA_WIDTH-1:0] combined;
begin
  // 等待一個上升沿開始送出
  @(posedge s00_axis_aclk);
  // 每次從陣列中取8筆資料打包
  for (idx = 0; idx < num_elements; idx = idx + 8) begin
    combined = { 
      ((idx+7 < num_elements) ? weight_buffer_array[idx+7][7:0] : 8'd0),
      ((idx+6 < num_elements) ? weight_buffer_array[idx+6][7:0] : 8'd0),
      ((idx+5 < num_elements) ? weight_buffer_array[idx+5][7:0] : 8'd0),
      ((idx+4 < num_elements) ? weight_buffer_array[idx+4][7:0] : 8'd0),
      ((idx+3 < num_elements) ? weight_buffer_array[idx+3][7:0] : 8'd0),
      ((idx+2 < num_elements) ? weight_buffer_array[idx+2][7:0] : 8'd0),
      ((idx+1 < num_elements) ? weight_buffer_array[idx+1][7:0] : 8'd0),
      ((idx   < num_elements) ? weight_buffer_array[idx][7:0]   : 8'd0)
    };
    s00_axis_tdata  = combined;
    s00_axis_tvalid = 1;
    // 當打包完最後一組（可能不足8筆）時，標記 tlast 為1
    s00_axis_tlast  = ((idx+8) >= num_elements) ? 1'b1 : 1'b0;
    // 等待下一個上升沿與 s00_axis_tready 信號
    @(posedge s00_axis_aclk);
    wait(s00_axis_tready);
  end
  // 送完後清除 tvalid 與 tlast
  s00_axis_tvalid = 0;
  s00_axis_tlast  = 0;
end
endtask

task send_all_weight(input integer data_file,input integer weight_file);
    integer scan_result;
    integer i;
    integer j;
    integer send_number;
    reg [7:0] data_buffer [0:2**MAX_ADDR_WIDTH-1];
    reg [7:0] weight0_buffer [0:2**MAX_ADDR_WIDTH-1];
    reg [7:0] weight1_buffer [0:2**MAX_ADDR_WIDTH-1];
    reg [7:0] weight2_buffer [0:2**MAX_ADDR_WIDTH-1];
    reg [7:0] weight3_buffer [0:2**MAX_ADDR_WIDTH-1];
begin
    $display("read_weight -> img_row = %d, img_col = %d, in_channel = %d, total = %d", img_row, img_col, in_channel,batch * img_col * img_row * in_channel);
    // scan_result = $fscanf(img_file, "%d %d %d %d\n", batch , img_row, img_col, in_channel);
    for (i = 0; i < op0_input_data_total_counts; i = i + 1) begin
        scan_result = $fscanf(img_file, "%d\n", data_buffer[i]);
        // $display("data_buffer[%d] = %d", i, data_buffer[i]);
    end

    // 讀取 weight row/col
    // scan_result = $fscanf(weight_file, "%d %d %d\n", out_channel , ker_row, ker_col);
    $display("read_weight -> ker_row = %d, out_channel = %d, ker_col = %d, in_channel = %d, total = %d", out_channel,ker_row, ker_col, in_channel, out_channel * ker_col * ker_row * in_channel);
    for (i = 0; i < op0_weight_total_counts; i = i + 1) begin
        scan_result = $fscanf(weight_file, "%d\n", weight0_buffer[i]);
        // $display("weight0_buffer[%d] = %d", i, weight0_buffer[i]);
    end
    // 讀取不同的op所需要的weight_buffer
    if(op1_weight_total_counts > 0) begin
        for (i = 0; i < op1_weight_total_counts; i = i + 1) begin
            scan_result = $fscanf(weight_file, "%d\n", weight1_buffer[i]);
            // $display("weight1_buffer[%d] = %d", i, weight1_buffer[i]);
        end
    end

    if(op2_weight_total_counts > 0) begin
        for (i = 0; i < op2_weight_total_counts; i = i + 1) begin
            scan_result = $fscanf(weight_file, "%d\n", weight2_buffer[i]);
            // $display("weight2_buffer[%d] = %d", i, weight2_buffer[i]);
        end
    end

    if(op3_weight_total_counts > 0) begin
        for (i = 0; i < op3_weight_total_counts; i = i + 1) begin
            scan_result = $fscanf(weight_file, "%d\n", weight3_buffer[i]);
            // $display("weight3_buffer[%d] = %d", i, weight3_buffer[i]);
        end
        send_weight_data(weight3_buffer, op3_weight_total_counts);
    end

    // 將讀取到的資料送出
    if(op2_weight_total_counts > 0) begin
        send_weight_data(weight2_buffer, op2_weight_total_counts);
    end

    if(op1_weight_total_counts > 0) begin
        send_weight_data(weight1_buffer, op1_weight_total_counts);
    end

    send_weight_data(data_buffer,op0_input_data_total_counts);
    send_weight_data(weight0_buffer,op0_weight_total_counts);
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
    reg signed [C_AXIS_MDATA_WIDTH-1:0] sum;
    reg signed [31:0] tmp_result;
    integer out_rows, out_cols;
    integer pad_h, pad_w;
    integer idx;

    // 根據 padding 信號決定上下左右需要補零的量
    if (padding) begin
        // SAME padding 假設補零量為 (ker_dim - 1)/2
        pad_h = (ker_row - 1) / 2;
        pad_w = (ker_col - 1) / 2;
    end else begin
        pad_h = 0;
        pad_w = 0;
    end
    if (padding) begin
        // SAME: 輸出尺寸等於 ceil(img_dim / stride)
        out_rows = (img_row + stride_h - 1) / stride_h;
        out_cols = (img_col + stride_w - 1) / stride_w;
    end else begin
        // VALID: 輸出尺寸 = floor((img_dim - ker_dim + 1) / stride)
        out_rows = (img_row - ker_row + 1) / stride_h;
        out_cols = (img_col - ker_col + 1) / stride_w;
    end

    // 遍歷每個 batch（假設 batch 為批次數）
    for (b = 0; b < batch; b = b + 1) begin
        // 遍歷輸出高度與寬度
        for (i = 0; i < out_rows; i = i + 1) begin
            for (j = 0; j < out_cols; j = j + 1) begin
                // 遍歷每個 output channel (out_channel)
                for (oc = 0; oc < out_channel; oc = oc + 1) begin
                    sum = 0;
                // 進行卷積運算 (MAC 累加)，遍歷 kernel 高度、寬度及所有輸入 channel
                for (m = 0; m < ker_row; m = m + 1) begin
                    for (n = 0; n < ker_col; n = n + 1) begin
                        for (ic = 0; ic < in_channel; ic = ic + 1) begin
                            // 計算輸入資料位置：
                            // 對應 NHWC 排列，輸入行位置 = i*stride_h - pad_h + m
                            // 輸入列位置 = j*stride_w - pad_w + n
                            // offset = (((b * img_row + (i*stride_h - pad_h + m)) * img_col + (j*stride_w - pad_w + n)) * img_in_channel) + ic
                            if (((i * stride_h - pad_h + m) < 0) ||
                                ((i * stride_h - pad_h + m) >= img_row) ||
                                ((j * stride_w - pad_w + n) < 0) ||
                                ((j * stride_w - pad_w + n) >= img_col)) begin
                            // 超出範圍，視作 0
                                sum = sum + 0;
                            end else begin
                                if(i==0 && j==0 && oc==10)
                                    $display("img_buffer[%d] = %d, weight_buffer[%d] = %d, sum = %d", (((b * img_row + (i * stride_h - pad_h + m)) * img_col + (j * stride_w - pad_w + n)) * in_channel) + ic, img_buffer[ (((b * img_row + (i * stride_h - pad_h + m)) * img_col + (j * stride_w - pad_w + n)) * in_channel) + ic], ((((oc) * ker_row + m) * ker_col + n) * in_channel) + ic, weight_buffer[ ((((oc) * ker_row + m) * ker_col + n) * in_channel) + ic],sum);
                                sum = sum + img_buffer[ (((b * img_row + (i * stride_h - pad_h + m)) * img_col + (j * stride_w - pad_w + n)) * in_channel) + ic ]
                                        *
                                        // 計算濾波器位置 (OHWC排列)
                                        // kernel 排序： [output_channel, ker_row, ker_col, in_channel]
                                        // offset = ((((oc) * ker_row + m) * ker_col + n) * img_in_channel) + ic
                                        weight_buffer[ ((((oc) * ker_row + m) * ker_col + n) * in_channel) + ic ];
                            end
                        end
                    end
                end

                // 計算輸出位置 offset (NHWC排列)
                // 輸出尺寸 = [batch, out_rows, out_cols, out_channel]
                // offset = (((b * out_rows + i) * out_cols + j) * out_channel) + oc
                idx = (((b * out_rows + i) * out_cols + j) * out_channel) + oc;
                
                // ========================================================
                // [A] 紀錄「requant前」的累加值 sum 到 sum_before_requant[]
                // ========================================================
                sum_before_requant[idx] = sum;
                $display("sum_before_requant[%d] = %d", idx, sum);
                
                // ========================================================
                // [B] 透過 golden_multiply_by_quantized_multiplier 進行 requant
                //     並 Clamp 結果至 int8 範圍 (-128 ~ 127)
                // ========================================================
                tmp_result = golden_multiply_by_quantized_multiplier(sum, test_q_multiplier, test_shift);
                if (tmp_result > 127)
                    expected_output[idx] = $signed(POS_127);
                else if (tmp_result < -128)
                    expected_output[idx] = $signed(NEG_128);
                else
                    expected_output[idx] = tmp_result;
                end
            end
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
    total_elements = ((img_row - ker_row + 1)/stride_w) * ((img_col - ker_col + 1)/stride_h) * out_channel;

    for(idx = 0; idx < total_elements; idx = idx + 1) begin
        // [A] Dequant
        // $display("idx = %d, original_data = %d", idx, expected_output[idx]);
        requant_minus_zero_point = expected_output[idx] - exp_deq_input_zero_point;
        if(requant_minus_zero_point >= $signed(exp_deq_input_range_radius)) begin
            exp_output[idx] = $signed(POS_127);
            $display("idx = %d, requant_minus_zero_point = %d in  1", idx,requant_minus_zero_point);
        end else if(requant_minus_zero_point <= $signed(-exp_deq_input_range_radius)) begin
            exp_output[idx] = $signed(NEG_128);
            $display("idx = %d, requant_minus_zero_point = %d in 2",idx,requant_minus_zero_point);
        end else begin
            dequant_val = golden_multiply_by_quantized_multiplier(requant_minus_zero_point, 
                            exp_deq_input_multiplier, exp_deq_input_left_shift);
            // $display("dequant_val = %h", dequant_val);
            // [B] exp_pipeline
            @(negedge s00_axis_aclk);
            input_valid_exp = 1;
            @(negedge s00_axis_aclk);
            input_valid_exp = 0;

            wait(output_valid_exp);
            $display("exp_x[%d] = %h", idx,exp_x);
            exp_output[idx] = exp_x;
        end

    end

end
endtask

// Instantiate exp_pipeline module
// exp_pipeline exp_inst(
//     .clk(s00_axis_aclk),
//     .rst(s00_axis_aresetn),
//     .x(dequant_val),
//     .integer_bits(4'd4),  // Q4.27 format
//     .input_valid(input_valid_exp),
//     .exp_x(exp_x),
//     .output_valid(output_valid_exp)
// );

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
    reg signed [7:0]  received_byte;   // 臨時儲存提取的有效位元組
begin
    // total_elements = (img_row - ker_row + 1)/stride_w * (img_col - ker_col + 1)/stride_h * out_channel;
    // total_elements = (img_row - ker_row + 1)/stride_w * (img_col - ker_col + 1)/stride_h * out_channel;
    total_elements = op0_data_counts;
    idx = 0;
    
    @(negedge m00_axis_aclk);
    m00_axis_tready = 1;
    
    // 等待第一個有效輸出
    wait(m00_axis_tvalid);

    while (m00_axis_tvalid && idx < total_elements) begin
        @(posedge m00_axis_aclk);
        
        // 讀取當前周期的數據和位元組使能
        received_data = m00_axis_tdata;
        // received_strb = m00_axis_tstrb;
        
        // 遍歷每個位元組，檢查哪些位元組有效
        for_loop : for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
            // if (received_strb[byte_idx]) begin
            // if (byte_idx < m00_axis_tstrb) begin
                // 提取有效位元組
                received_byte = received_data[byte_idx*8 +: 8];
                
                // 比較有效位元組與預期輸出
                // if (received_byte !== expected_output[idx]) begin
                // if (received_byte !== exp_output[idx][7:0]) begin
                //     $display("Mismatch at element %d, byte %d: expected=%h, got=%h", 
                //              idx, byte_idx, exp_output[idx][7:0], received_byte);
                //     $finish;
                // end else begin
                //     $display("Match at element %d, byte %d: %h", idx, byte_idx, received_byte);
                // end
                // $display("Got %d at %d", received_byte, idx);
                idx = idx + 1; // 每處理一個有效位元組，移動到下一個預期元素
                if(idx >= total_elements) 
                    disable for_loop; // 如果讀取完所有預期元素，則退出循環
            // end
        end
        
        // 等待下一個數據周期
        // 如果需要處理 m00_axis_tvalid 的變化，可在此加入額外邏輯
    end

    // if(idx < total_elements) begin
    //     $display("Error: fewer outputs received than expected. Received: %d, Expected: %d", idx, total_elements);
    //     $finish;
    // end
end
endtask

//----------------------------------------------
// 18) 設定 metadata 到NPU的輸入 port（僅設定metadata相關訊號）, metadata_done, metadata_valid_i
//----------------------------------------------
task send_metadata(input metadata_t meta);
begin
  // 設定 Convolution 參數
  batch      = meta.batch;
  img_row    = meta.img_row;
  img_col    = meta.img_col;
  in_channel = meta.in_channel;
  out_channel= meta.out_channel;
  ker_row    = meta.ker_row;
  ker_col    = meta.ker_col;
  stride_h   = meta.stride_h;
  stride_w   = meta.stride_w;
  padding    = meta.padding;

  // conv requant 參數
  test_q_multiplier = meta.conv_requant_multiplier;
  test_shift = meta.conv_requant_shift;
  test_output_offset = meta.conv_requant_output_offset;

  // 設定 op 及 weight 相關訊號
  op         = meta.op;
  weight_num = meta.weight_num;
  store_sram_idx0 = meta.store_sram_idx;
  op0_weight_sram_idx0 = meta.op0_weight_idx[0];
  op0_weight_sram_idx1 = meta.op0_weight_idx[1];
  op1_weight_sram_idx0 = meta.op1_weight_idx0;
  op2_weight_sram_idx0 = meta.op2_weight_idx0;
  op3_weight_sram_idx0 = meta.op3_weight_idx0;
  op0_broadcast = meta.op0_broadcast;
  op1_broadcast = meta.op1_broadcast;
  op2_broadcast = meta.op2_broadcast;
  op3_broadcast = meta.op3_broadcast;
  op0_data_counts = meta.op0_data_counts;
  op1_data_counts = meta.op1_data_counts;
  op2_data_counts = meta.op2_data_counts;
  op3_data_counts = meta.op3_data_counts;
  op0_input_data_total_counts = meta.op0_input_data_total_counts;
  op0_weight_total_counts = meta.op0_weight_total_counts;
  op1_weight_total_counts = meta.op1_weight_total_counts;
  op2_weight_total_counts = meta.op2_weight_total_counts;
  op3_weight_total_counts = meta.op3_weight_total_counts;

  // 設定 Exp 相關
  exp_deq_input_range_radius = meta.exp_deq_input_range_radius;
  exp_deq_input_zero_point   = meta.exp_deq_input_zero_point;
  exp_deq_input_multiplier   = meta.exp_deq_input_multiplier;
  exp_deq_input_left_shift   = meta.exp_deq_input_left_shift;
  exp_req_input_quantized_multiplier = meta.exp_req_input_quantized_multiplier;
  exp_req_input_shift = meta.exp_req_input_shift;
  exp_req_input_offset = meta.exp_req_input_offset;

  // 設定 Reciprocal 相關
  reciprocal_deq_input_range_radius = meta.reciprocal_deq_input_range_radius;
  reciprocal_deq_input_zero_point   = meta.reciprocal_deq_input_zero_point;
  reciprocal_deq_input_multiplier   = meta.reciprocal_deq_input_multiplier;
  reciprocal_deq_input_left_shift   = meta.reciprocal_deq_input_left_shift;
  reciprocal_req_input_quantized_multiplier = meta.reciprocal_req_input_quantized_multiplier;
  reciprocal_req_input_shift = meta.reciprocal_req_input_shift;
  reciprocal_req_input_offset = meta.reciprocal_req_input_offset;

  // 設定 ADD 相關
  add_input1_offset = meta.add_input1_offset;
  add_input2_offset = meta.add_input2_offset;
  add_left_shift    = meta.add_left_shift;
  add_input1_multiplier = meta.add_input1_multiplier;
  add_input2_multiplier = meta.add_input2_multiplier;
  add_input1_shift  = meta.add_input1_shift;
  add_input2_shift  = meta.add_input2_shift;
  add_output_multiplier = meta.add_output_multiplier;
  add_output_shift  = meta.add_output_shift;
  add_output_offset = meta.add_output_offset;
  add_quantized_activation_min = meta.add_quantized_activation_min;
  add_quantized_activation_max = meta.add_quantized_activation_max;

  // 設定 SUB 相關
  sub_input1_offset = meta.sub_input1_offset;
  sub_input2_offset = meta.sub_input2_offset;
  sub_left_shift    = meta.sub_left_shift;
  sub_input1_multiplier = meta.sub_input1_multiplier;
  sub_input2_multiplier = meta.sub_input2_multiplier;
  sub_input1_shift  = meta.sub_input1_shift;
  sub_input2_shift  = meta.sub_input2_shift;
  sub_output_multiplier = meta.sub_output_multiplier;
  sub_output_shift  = meta.sub_output_shift;
  sub_output_offset = meta.sub_output_offset;
  sub_quantized_activation_min = meta.sub_quantized_activation_min;
  sub_quantized_activation_max = meta.sub_quantized_activation_max;

  // 設定 MUL 相關
  mul_input1_offset = meta.mul_input1_offset;
  mul_input2_offset = meta.mul_input2_offset;
  mul_output_multiplier = meta.mul_output_multiplier;
  mul_output_shift = meta.mul_output_shift;
  mul_output_offset = meta.mul_output_offset;
  mul_quantized_activation_min = meta.mul_quantized_activation_min;
  mul_quantized_activation_max = meta.mul_quantized_activation_max;

  // 設定metadata控制訊號，這裡只需要在一個週期內將metadata送入即可
  @(negedge s00_axis_aclk);
  metadata_valid_i = 1;
  metadata_done = 0;
  @(negedge s00_axis_aclk);
  metadata_valid_i = 0;
  metadata_done = 1;
//   repeat(10)@(negedge s00_axis_aclk);
//   metadata_done = 0;
  $display("send_metadata: op=%b, weight_num=%0d", meta.op, meta.weight_num);
end
endtask

//----------------------------------------------
// 19) 主控 Flow
//----------------------------------------------
initial
begin
    img_file = $fopen("image_data.txt", "r");
    weight_file = $fopen("kerenl_data.txt", "r");
    wait(s00_axis_aresetn && m00_axis_aresetn);
    @(posedge s00_axis_aclk);
    $display("start model simulation!!!!!!");
    
    compute_convolution(); // 同時產生 sum_before_requant[] & expected_output[]
    compute_exp_after_requant(); // 產生 exp_output[]

    read_metadata(metadata[0:9999], num_ops);
    // $finish;
    for(i=0; i<num_ops; i=i+1) begin
        $display("the %d op starts!!!!!!!!!!!!!!!!!",i);
        send_metadata(metadata[i]);
        $display("op0_data_counts = %d", op0_data_counts);
        send_all_weight(img_file, weight_file);
    // read_weight();
    // for(i = 0; i < num_ops; i = i + 1) begin
    // send_image();
    // send_weight();
    // end
    // send_metadata(metadata);
    // send_image();
    // send_weight();
        metadata_done = 0; 
        wait(layer_calc_done);
        @(negedge s00_axis_aclk);
        $display("num_ops = %d",num_ops);
        // if(i==250) $finish;
    end
    finish_calc = 1;
    wait(m00_axis_tvalid);
    check_output(); // Compare & print requant前/後
    $fclose(img_file);
    $fclose(weight_file);

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
    $display("sram_access_counts : %d", sram_access_counts);
    $display("dram_access_counts : %d", dram_access_counts);
    $display("elementwise_idle_counts : %d", elementwise_idle_counts);
    $finish;
end

endmodule
