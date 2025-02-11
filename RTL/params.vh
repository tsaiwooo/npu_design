// for FSM
// State definitions using localparam

`ifndef PARAMS_VH
`define PARAMS_VH  
// FSM states
localparam IDLE         = 0;
localparam LOAD_IMG         = 1;
localparam LOAD_KER         = 2;
localparam COMPUTE_CONV0 = 3;
localparam COMPUTE_CONV1 = 4;
localparam WAIT_LAST = 5;
// localparam ACTIVATION   = 3'd4;
localparam WRITE_OUTPUT = 6;

// for multi_sram paramaters        
localparam NUM_SRAMS = 8;
localparam int DATA_WIDTHS[0:NUM_SRAMS-1] = '{8, 8, 8, 8, 8, 8, 8, 8};

`ifndef synthesis
    localparam int N_ENTRIES[0:NUM_SRAMS-1] = '{262144, 262144, 262144, 262144, 
                                                262144, 262144, 262144, 262144};
`else
    localparam int N_ENTRIES[0:NUM_SRAMS-1] = '{4, 4, 4, 4, 
                                                4, 4, 4, 4};
`endif

localparam [7:0] GEMM0_SRAM_IDX = 0, GEMM1_SRAM_IDX=1, GEMM2_SRAM_IDX=2, ELEM0_SRAM_IDX=3, ELEM1_SRAM_IDX=4, ELEM2_SRAM_IDX=5, DEQUANT0_SRAM_IDX=6, DEQUANT1_SRAM_IDX=7;
localparam MAX_ADDR_WIDTH = 18; 
localparam MAX_DATA_WIDTH = 32;

// control sram parameters
localparam SRAM_WIDTH_O = 64;

// data bandwidth
localparam INT8_WIDTH = 8;
`endif  // PARAMS_VH
