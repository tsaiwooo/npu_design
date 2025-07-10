# npu_design
desing NPU which MAC unit and elementwize engine can run concurrently

## Branch
### Vector
OEM Design, Implements a 
* pipelined architecture enabling concurrent execution of the MAC and element-wise units to maximize hardware utilization and throughput
* intermediate tensor reuse

### layer_by_layer
OEM-I, Implements a 
* sequential execution
* intermediate tensor reuse
