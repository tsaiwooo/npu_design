# npu_design
desing NPU which MAC unit and elementwize engine can run concurrently

## Makefile
- change two lines with your design and testbench
```c=
DESIGN_FILE = xxx.v
TESTBENCH_FILE = xxx.v
```

## Module introduction
### GEMM
- 各種需要用到MAC unit的運算會在這裡, ex: conv, fully connected etc.

### element-wize 
- 各種非GEMM運算, ex: exp, reciprocal, add etc.

### Mac unit
- support signed dynamic macs, which means that input and weight can use 1~64 macs to calculate

### sram
- use multi-sram, 且每一個都存不同運算的result, read sram給一個address, 吐出64bits資料, 所以根據sram input data_width, 可能一次有8, 4, 2筆資料 

### sram controller
- 整理各個sram input and output的訊號, 透過sram controller去跟sram溝通 

### MultiplyByQuantizedMultiplier
- 32bits input 乘上quantized_multiplier, 然後再透過shift做量化縮放

### RoundingDivideByPOT
- 對32bits input 除以$2^{exponent}$ 並且計算是否需要四捨五入(rounding arithmetic right shift)

### exp
- pipeline exp運算

## stage
### stage1
- 透過axi4-stream傳matrix到sram[GEMM0_SRAM_IDX], kernel到sram[GEMM1_SRAM_IDX], 傳完後用mac unit做convolution傳到sram[GEMM0_SRAM_IDX]
- 使用tb_npu

### stage2 
- 新增一個element-wise engine, 做完convolution後element-wize再拿sram[GEMM0_SRAM_IDX]的資料做運算再傳到sram[GEMM1_SRAM_IDX]
- tb_npu_2

### stage3
- 要concurrent做運算, 也就是部份convolution做完後elemen-wize開始拿result運算, convolution繼續做且存到另一個buffer等等
- tb_npu3 

## FURURE WORK
- 看sram bandwidth 是否能增大, 一次拿多筆資料增加throughput
- 或是使用multi-bank, 獨立的