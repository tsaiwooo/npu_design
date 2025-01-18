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
- 最多一次支援8組資料做運算 -> 增加pe使用率

### sram
- use multi-sram, 且每一個都存不同運算的result, read sram給一個address, 吐出64bits資料, 所以根據sram input data_width, 可能一次有8, 4, 2筆資料 

### sram controller
- 整理各個sram input and output的訊號, 透過sram controller去跟sram溝通 

### MultiplyByQuantizedMultiplier
- 32bits input 乘上quantized_multiplier, 然後再透過shift做量化縮放, output是32bits, 最後出去再看是否超過int8上下限, 再把值域縮放到int8

### RoundingDivideByPOT
- 對32bits input 除以$2^{exponent}$ 並且計算是否需要四捨五入(rounding arithmetic right shift)

### exp
- pipeline exp運算泰勒展開式

### reciprocal
- pipeline運算, 使用 Newton–Raphson division (https://en.wikipedia.org/wiki/Newton%27s_method), 支援Q1.1.30 ~ Q1.4.27 且必須 >1

## stage
### stage1
- 透過axi4-stream傳matrix到sram[GEMM0_SRAM_IDX], kernel到sram[GEMM1_SRAM_IDX], 傳完後用mac unit做convolution傳到sram[GEMM0_SRAM_IDX]
- 使用tb_npu

### stage2 
- 新增一個element-wise engine, 做完convolution(使用multi-set mac)後做requant存至sram[GEMM0_SRAM_IDX], 然後convolution到requant中間使用一個FIFO
- tb_npu1

### stage3
- convolution + requant(vector), 中間會先dequant再做運算然後存到sram[GEMM0_SRAM_IDX], requant使用vector(bandwidth: 8)
- tb_npu2

### stage4
- convolution + requant + exp, 接上element-wise的運算, 中間會先dequant再做運算然後存到sram[GEMM0_SRAM_IDX]
- tb_npu3 

## FURURE WORK
- 看sram bandwidth 是否能增大, 一次拿多筆資料增加throughput
- 或是使用multi-bank, 

## Logistic in tflm
```c=
inline void Logistic(int32_t input_zero_point, int32_t input_range_radius,
                     int32_t input_multiplier, int32_t input_left_shift,
                     int32_t input_size, const int8_t* input_data,
                     int8_t* output_data) {
  // Integer bits must be in sync with Prepare() function.
  static constexpr int32_t kInputIntegerBits = 4;
  static constexpr int32_t kOutputIntegerBits = 8;
  static constexpr int8_t kMinInt8 = std::numeric_limits<int8_t>::min();
  static constexpr int8_t kMaxInt8 = std::numeric_limits<int8_t>::max();
  static constexpr int32_t kOutputZeroPoint = -128;

  for (int i = 0; i < input_size; ++i) {
    const int32_t input =
        static_cast<int32_t>(input_data[i]) - input_zero_point;
    if (input <= -input_range_radius) {
      output_data[i] = kMinInt8;
    } else if (input >= input_range_radius) {
      output_data[i] = kMaxInt8;
    } else {
      const int32_t input_in_q4 = MultiplyByQuantizedMultiplier(
          input, input_multiplier, input_left_shift);
      using FixedPoint4 = gemmlowp::FixedPoint<int32_t, kInputIntegerBits>;
      const int32_t output_in_q0 =
          gemmlowp::logistic(FixedPoint4::FromRaw(input_in_q4)).raw();

      // Rescale and downcast.
      using gemmlowp::RoundingDivideByPOT;
      int32_t output_in_q23 =
          RoundingDivideByPOT(output_in_q0, 31 - kOutputIntegerBits);
      output_in_q23 = std::min(std::max(output_in_q23 + kOutputZeroPoint,
                                        static_cast<int32_t>(kMinInt8)),
                               static_cast<int32_t>(kMaxInt8));
      output_data[i] = static_cast<int8_t>(output_in_q23);
    }
  }
}
```