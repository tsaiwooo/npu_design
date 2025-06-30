# npu_design
desing NPU which MAC unit and elementwize engine can run concurrently

都在pc03跑, 要先license EDA tools
```
source /usr/cad/setlic.bashrc
```
## clone
先進到pc03自己的~/
```
git clone -b vector git@github.com:tsaiwooo/npu_design.git
```
## Run
去Makefile裡面確認是否是跑這tb, 如果之後要跑其他的也可以改, 或是全部的Makefile自己重寫也可以, 我也沒寫很好
```
TESTBENCH_FILE = tb_model.sv
```
[從這](https://drive.google.com/drive/folders/1BW6BpjYJSXzhFQMXOsQQcrQkeGRxF0vk)選model, 推薦先選part-efficient跑, 其他有些會跑比較久(1~2天以上), 點進去選不是baseline的數據, 複製到metadata.txt後下`make`就可以了
### tb_model.sv flow
- BIN loading–At reset the test-bench reads the compiler-generated BIN file into simulated DRAM (or directly into on-chip SRAM via $readmemh).
- DMA phase –The CPU model programs DMA descriptors that stream the declared weight_num tiles to the NPU’s DMA-I/O port; the port writes them into the indexed SRAM banks.
- Metadata handshake–After the last weight burst the test-bench asserts metadata_done, enabling the NPU to begin execution.
- Execution–The Operator Decoder slices the 16-bit op word into four 4-bit engine codes. The scheduler fetches operands from the indicated banks, drives the 8 Œ 8 MAC mesh, passes partial sums through a one-cycle buffer, and feeds the vectorised element-wise lanes, thus forming a single hazard-free pipeline. A hardware counter increments until data_result_counts is reached, whereupon the block raises op_done.
- Next micro-pipeline - The host streams the next weight set and metadata; steps 3–4 repeat until the entire model completes and a finish flag is generated.
- Result return - Final output tiles are burst-written back to DRAM via the DMA engine, where the test-bench compares them against golden reference tensors.

## 檔案
* `rtl` folder下面放design
* `TESTBENCH` folder下面放tb
> 如果有新的desing要測, 去makefile改`TESTBENCH_FILE` 改成要的file, 然後把desgin加進去`DESIGN_SRC`, 下Make就可以了
Makefile裡面很亂,所以可以自己寫一個:+1:, 都是用VCS, verdi

## metadata格式
先根據op, 每4bits切一個, 根據op會有對應的metadata
:::spoiler metadata format(OEM)
```c=
##################################################
# Control the flow of npu
# metadata info
# 1234567890 -> no more metadata info
##################################################

#############################################################################
########                      op0                                 ###########
##################################################
#  4'b0000: No operation -> idle
#  4'b0001: Conv
#  4'b0010: Fc
#  4'b0011: Exp
#  4'b0100: Reciprocal
#  4'b0101: ADD
#  4'b0110: SUB
#  4'b0111: MUL
# op: 1 operation with 4 bits, total 16bits
0100001101100001
##################################################

##################################################
# weight num, how many weights are used in the operation
3
##################################################

##################################################
# there are 8 srams in the design
# store_sram_idx, op0_weight_idx0, op0_weight_idx1, op1_weight_idx0, op2_weight_idx0, op3_weight_idx0
2 0 1 3 0 0
##################################################

##################################################
# op0_boradcast, op1_boradcast, op2_boradcast, op3_boradcast, 0 -> no, 1 -> weight, 2 -> data
0 1 0 0
# op0_data_counts, op1_data_counts, op2_data_counts, op3_data_counts
65536 65536 65536 65536
# op0_input_data_total_counts, op0_weight_total_counts, op1_weight_total_counts, op2_weight_total_counts, op3_weight_total_counts
0 0 1 0 0
##################################################

##################################################
# convolution signals
# stride_h, stride_w, padding
2 2 0
# image size [N,H,W,C] -> batch size, height, width, in_channel
1 130 130 3
# kernel size [O,H,W,C] -> out_channel, ker_height, ker_width, in_channel and in_channel will be ignored
16 3 3
# conv_requant_multiplier, conv_requant_shift, conv_output_offset
1422604838 -2 0
##################################################

##################################################
# exp signals
# exp_deq_input_range_radius, exp_deq_input_zero_point, exp_deq_input_multiplier, exp_deq_input_left_shift, exp_req_input_quantized_multiplier, exp_req_input_shift, exp_req_input_offset
480 0 1422604838 -2 1347588939 -4 26
##################################################

##################################################
# reciprocal signals
# reciprocal_deq_input_range_radius, reciprocal_deq_input_zero_point, reciprocal_deq_input_multiplier, reciprocal_deq_input_left_shift, reciprocal_req_input_quantized_multiplier, reciprocal_req_input_shift, reciprocal_req_input_offset
##################################################
480 0 1347588939 -4 1077521395 -7 0
##################################################
# ADD signals
# input1_offset, input2_offset, left_shift = 20, input1_multiplier, input2_multiplier, input1_shift, input2_shift, output_multiplier, output_shift, output_offset, quantized_activation_min, quantized_activation_max
0 0 20 0 0 0 0 0 0 0 -128 127
##################################################

##################################################
# SUB signals
# input1_offset, input2_offset, left_shift = 20, input1_multiplier, input2_multiplier, input1_shift, input2_shift, output_multiplier, output_shift, output_offset, quantized_activation_min, quantized_activation_max
0 0 20 0 1422604838 0 -2 1422604838 -2 0 -128 127
##################################################

##################################################
# MUL signals
# input1_offset, input2_offset, output_multiplier, output_shift, output_offset, quantized_activation_min, quantized_activation_max
0 0 0 0 0 -128 127
##################################################
1234567890
```
:::

## Architecture
### Op scheduler & op decoder
目前op decoder是直接傳, 沒有透過任何protocal,然後op scheduler會根據傳過來的op[15:0]來做處理, 每4個bits拆成一個op, 每個op會把算完的資料傳回到op scheduler, 裡面會再根據下一個op後把資料傳過去, 節省存取sram的時間, 直到所有op0~op3或是op已經是空的時候, 就會把資料存回sram
```
4'b0000: No operation -> idle
4'b0001: Conv
4'b0010: Fc
4'b0011: Exp
4'b0100: Reciprocal
4'b0101: ADD
4'b0110: SUB
4'b0111: MUL
```
### sram_controller
共有8個bank,每個op都會有對應到的bank, 可以增加throughtput, 以及減少bank conflict問題， 每個op要存取的bank是透過compiler傳過來的
> [!WARNING]
> **SRAM 存取行為重要提醒**
>
> - **Read (讀取)**：
>   - Address 是以 **byte** 為單位。
>   - 會回傳從給定 Address 開始的**連續 8 bytes** 資料。
>   - (範例：給定 Address `7`，會回傳位址 `7` 到 `14` 的資料)
>
> - **Write (寫入)**：
>   - Address 是以 **word line** 為單位 (每 8 bytes 為一個 word line)。
>
> - **若要修改此行為**，需要直接變更 SRAM 內部的操作邏輯。

### elementwise engine
1. 共有ADD,SUB,MUL,EXP,RECIPROCAL, 並且全部都是用vector(width=8) and pipeline
2. 都會先做dequant後做完運算再做requant
- EXP: 使用泰勒展開式 10 stages
- RECIPROCAL: 使用[Newton–Raphson division](https://en.wikipedia.org/wiki/Newton%27s_method) 13 stages, 支援Q1.1.30 ~ Q1.4.27 且必須 >1

### mac engine
64個pe, 使用inner product, 會想辦法根據kernel大小讓pe使用滿 ex: kernel : $3*3$, 則一次會計算出$64/9 = 7$個results, 若是kernel數目超過64，則外面會累加， 直到算完
### axi stream input & output
input module: 接收cpu傳來的資料(不同op的weight), 處理axi4 stream signals, 如果要改需要改傳到哪個sram bank, cpu傳來的資料
```
always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
    if (!s_axis_aresetn)
        data_type <= 0;
    else if (s_axis_tvalid && s_axis_tready) begin
        // weight_num == 4: 3 cases, op1, op2, op3 -> 1,1,0 or 1,0,1 or 0,1,1(1 represents that need weight)
        case(weight_num_reg_o)
            1: data_type <= op0_weight_sram_idx0;
            2: data_type <= op0_weight_sram_idx1;
            3: data_type <= (op1_weight_sram_idx0)? op1_weight_sram_idx0 :
                            (op2_weight_sram_idx0)? op2_weight_sram_idx0 :
                            (op3_weight_sram_idx0)? op3_weight_sram_idx0 : 0;
            4: data_type <= (op1_weight_sram_idx0 != 0 && op2_weight_sram_idx0 !=0 && op2_weight_sram_idx0 == 0)? op2_weight_sram_idx0:
                            (op1_weight_sram_idx0 != 0 && op3_weight_sram_idx0 ==0 && op3_weight_sram_idx0 != 0)? op3_weight_sram_idx0:
                            (op1_weight_sram_idx0 == 0 && op2_weight_sram_idx0 != 0 && op3_weight_sram_idx0 != 0)? op3_weight_sram_idx0: 0;
            5: data_type <= op3_weight_sram_idx0;
            default: data_type <= 0;
        endcase
        // if (state == ST_IMG)
        //     data_type <= op0_weight_sram_idx0;
        // else if (state == ST_KER)
        //     data_type <= op0_weight_sram_idx1;
        // else
        //     data_type <= data_type; // keep unchanged
    end else
        data_type <= data_type; // keep unchanged
end
```
output module: 傳送result回cpu, 也是處理axi4 stream signals
### alignment
資料算完有可能是1~8筆, 而不是完整地8筆, 還有目前sram bandwidth是64bits, 為了不讓zero出現在資料中間而使用的unit

### quantization
基本上參考tflm的操作方式
```
inline int32_t MultiplyByQuantizedMultiplier(int32_t x,
                                             int32_t quantized_multiplier,
                                             int shift) {
  using gemmlowp::RoundingDivideByPOT;
  using gemmlowp::SaturatingRoundingDoublingHighMul;
  int left_shift = shift > 0 ? shift : 0;
  int right_shift = shift > 0 ? 0 : -shift;
  return RoundingDivideByPOT(SaturatingRoundingDoublingHighMul(
                                 x * (1 << left_shift), quantized_multiplier),
                             right_shift);
}
```