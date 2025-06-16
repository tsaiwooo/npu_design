// for FSM
// State definitions using localparam
// for synthesis macro, 減少sram大小(flip-flop數量)
// `define synthesis


`ifndef PARAMS_VH
`define PARAMS_VH  
// FSM states
// -------------------------------------------------
// WAIT_META: wait cpu for metadata
// WAIT_OP  : wait npu calculation
// OP_DONE  : npu calculation done, layer_calc_done = 1
// -------------------------------------------------
localparam [2:0] IDLE         = 0;
localparam [2:0] WAIT_META = 1;
localparam [2:0] WAIT_OP    = 2;
localparam [2:0] OP_DONE    = 3;
// localparam [2:0] LOAD_IMG         = 1;
// localparam [2:0] LOAD_KER         = 2;
// localparam [2:0] COMPUTE_CONV0 = 3;
// localparam [2:0] COMPUTE_CONV1 = 4;
localparam [2:0] WAIT_LAST = 5;
// localparam ACTIVATION   = 3'd4;
localparam [2:0] WRITE_OUTPUT = 6;

// for multi_sram paramaters        
localparam NUM_SRAMS = 8;
localparam [31:0] DATA_WIDTHS[0:NUM_SRAMS-1] = '{64, 64, 64, 64, 64, 64, 64, 64
                                             };
`ifndef synthesis
// localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{262144, 262144, 262144, 262144, 262144, 262144, 262144, 262144
//                                              };
localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{2097152, 2097152, 2097152, 2097152, 2097152, 2097152, 2097152, 2097152
                                             };
`else
localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{4, 4, 4, 4, 4, 4, 4, 4
                                             };
`endif
localparam [2:0] GEMM0_SRAM_IDX = 0, GEMM1_SRAM_IDX=1, GEMM2_SRAM_IDX=2, ELEM0_SRAM_IDX=3, ELEM1_SRAM_IDX=4, DEQUANT0_SRAM_IDX=5, DEQUANT1_SRAM_IDX=6, RESULT_OUT=7;
// localparam MAX_ADDR_WIDTH = 18; 
localparam MAX_ADDR_WIDTH = 22; 
localparam MAX_DATA_WIDTH = 32;

// for 64bits sram parameters
localparam sram_64bits_width = 64;
`ifndef synthesis
localparam sram_64bits_depth = 65536;
`else
localparam sram_64bits_depth = 128;
`endif

// control sram parameters
localparam SRAM_WIDTH_O = 64;

// data size
localparam INT8_SIZE = 8;
localparam INT32_SIZE = 32;
localparam INT64_SIZE = 64;

// exp mul pipeline depth
localparam MUL_DEPTH = 2; 
// MultiplyByQuantizedMultiplierSmallerThanOneExp DEPTH
// localparam DEPTH = 3;
`endif  // PARAMS_VH
