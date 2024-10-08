# npu_design
desing NPU which MAC unit and elementwize engine can run concurrently

## Makefile
- change two lines with your design and testbench
```c=
DESIGN_FILE = xxx.v
TESTBENCH_FILE = xxx.v
```
## Mac unit
- support dynamic macs, which means that input and weight can use 1~64 macs to calculate

## sram
