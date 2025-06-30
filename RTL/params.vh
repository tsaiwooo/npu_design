// for FSM
// State definitions using localparam

`ifndef PARAMS_VH
`define PARAMS_VH  
// OP_CODE
localparam IDLE_OP = 4'b0000;   // No operation -> idle
localparam CONV_OP = 4'b0001;   // Convolution
localparam FC_OP = 4'b0010;     // Fully Connected
localparam EXP_OP = 4'b0011;    // Exponential
localparam RECIPROCAL_OP = 4'b0100; // Reciprocal
localparam ADD_OP = 4'b0101;   // Addition
localparam SUB_OP = 4'b0110;   // Subtraction
localparam MUL_OP = 4'b0111;   // Multiplication
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
// localparam IDLE         = 0;
// localparam LOAD_IMG         = 1;
// localparam LOAD_KER         = 2;
// localparam COMPUTE_CONV0 = 3;
// localparam COMPUTE_CONV1 = 4;
localparam WAIT_LAST = 5;
// localparam ACTIVATION   = 3'd4;
localparam WRITE_OUTPUT = 6;

// for multi_sram paramaters        
localparam NUM_SRAMS = 8;
localparam [31:0] DATA_WIDTHS[0:NUM_SRAMS-1] = '{64, 64, 64, 64, 64, 64, 64, 64};

`ifndef synthesis
// localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{262144, 262144, 262144, 262144, 262144, 262144, 262144, 262144
//                                              };
    localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{2097152, 2097152, 2097152, 2097152, 
                                                2097152, 2097152, 2097152, 2097152};
`else
    localparam [31:0] N_ENTRIES[0:NUM_SRAMS-1] = '{4, 4, 4, 4, 
                                                4, 4, 4, 4};
`endif

localparam [2:0] GEMM0_SRAM_IDX = 0, GEMM1_SRAM_IDX=1, GEMM2_SRAM_IDX=2, ELEM0_SRAM_IDX=3, ELEM1_SRAM_IDX=4, ELEM2_SRAM_IDX=5, DEQUANT0_SRAM_IDX=6, DEQUANT1_SRAM_IDX=7;
// localparam MAX_ADDR_WIDTH = 18; 
parameter MAX_ADDR_WIDTH = 22; 
parameter MAX_DATA_WIDTH = 32;

// control sram parameters
localparam SRAM_WIDTH_O = 64;

// data size
localparam INT8_SIZE = 8;
localparam INT32_SIZE = 32;
localparam INT64_SIZE = 64;
// exp mul pipeline depth
localparam MUL_DEPTH = 2; 
`endif  // PARAMS_VH
