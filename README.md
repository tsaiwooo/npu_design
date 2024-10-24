# npu_design
desing NPU which MAC unit and elementwize engine can run concurrently

## Makefile
- change two lines with your design and testbench
```c=
DESIGN_FILE = xxx.v
TESTBENCH_FILE = xxx.v
```
## Mac unit
- support signed dynamic macs, which means that input and weight can use 1~64 macs to calculate

## sram
- use multi-sram, 且每一個都存不同運算的result


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