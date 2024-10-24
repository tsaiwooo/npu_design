// sram_dp 是scratch memory, 不是真正的sram
// 真正的sram只能read or write 且等到下一個cycle才能拿到資料
// FUTURE WORK: 1. 第一筆資料或是透過傳register的方式知道是幾*幾的kernel, 然後分別存在不同的sram, 這樣就可以減少cycle數, 缺點： 不知道到底會需要多少個sram
// FUTURE WORK: 2. 還有加快速度的方法就是給一個address, 然後拿後面N筆連續資料
/****************             current flow            ****************/
/*      dma transfer image to sram[GEMM0_SRAM_IDX]                   */
/*      dma transfer kernel to sram[GEMM1_SRAM_IDX]                  */
/*      compute convolution and store result to sram[ELEM0_SRAM_IDX] */
/*      dma transfer result from sram[ELEM0_SRAM_IDX] to output      */
`timescale 1ns / 1ps
`include "params.vh"

module npu#
(
    parameter MAX_MACS = 64,
    parameter ADDR_WIDTH = 13,
    parameter C_AXIS_TDATA_WIDTH = 8,
    parameter C_AXIS_MDATA_WIDTH = 8,
    parameter MAX_CHANNELS = 64,
    parameter NUM_CHANNELS_WIDTH = $clog2(MAX_CHANNELS+1)
)
(
    /* AXI slave interface (input to the FIFO) */
    input  wire                   s00_axis_aclk,
    input  wire                   s00_axis_aresetn,
    input  wire signed [C_AXIS_TDATA_WIDTH-1:0]  s00_axis_tdata,
    input  wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tstrb,
    input  wire                   s00_axis_tvalid,
    output wire                   s00_axis_tready,
    input  wire                   s00_axis_tlast,
    input  wire [ 2*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser,  // use for channel number

    
    /* * AXI master interface (output of the FIFO) */
    input  wire                   m00_axis_aclk,
    input  wire                   m00_axis_aresetn,
    output reg signed [2*C_AXIS_MDATA_WIDTH-1:0]  m00_axis_tdata,
    output reg [(C_AXIS_MDATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
    output reg                   m00_axis_tvalid,
    input  wire                   m00_axis_tready,
    output reg                   m00_axis_tlast,
    output reg [NUM_CHANNELS_WIDTH-1:0] m00_axis_tuser  // use for channel number
);
    localparam ST_IMG=0;
    localparam ST_KER=1;
    reg [1:0] ST_state = 0; // use for store data from axi4-stream

    // sram input and output signals
    reg [NUM_SRAMS-1:0] en;
    reg [NUM_SRAMS-1:0] we;
    reg [NUM_SRAMS * MAX_ADDR_WIDTH - 1 : 0] addr;
    reg [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_in;
    wire [NUM_SRAMS * MAX_DATA_WIDTH - 1 : 0] data_out;


    reg [3:0] state = 4'd0, next_state;  // Current state of the FSM

    // img_row, img_col, ker_row, ker_col
    wire [ADDR_WIDTH-1:0] img_row, img_col, ker_row, ker_col;
    reg [ADDR_WIDTH-1:0] img_row_reg, img_col_reg, ker_row_reg, ker_col_reg;

    // mac_gen signals
    wire [ NUM_CHANNELS_WIDTH - 1 : 0] num_macs_i;
    reg [C_AXIS_TDATA_WIDTH * MAX_CHANNELS - 1 : 0] data_mac_i;
    reg [C_AXIS_TDATA_WIDTH * MAX_CHANNELS - 1 : 0] weight_mac_i;
    wire signed [ 2*C_AXIS_MDATA_WIDTH - 1 : 0] mac_out;
    wire mac_valid_out;
    wire mac_valid_in;

    // MAC result
    wire [C_AXIS_TDATA_WIDTH*MAX_CHANNELS-1:0] mac_result;
    // cur_img_row, cur_img_col
    reg [ADDR_WIDTH-1:0] idx1_img, idx1_ker, idx1_out;
    
    // sram_img signals
    wire [NUM_CHANNELS_WIDTH-1: 0]num_channels1_img_i,num_channels1_ker_i;
    assign s00_axis_tready = s00_axis_tvalid;
    reg last_data, last_data_reg;
    reg we1_img_i_reg;

    assign { img_row , img_col , num_channels1_img_i } = (s00_axis_tlast && state == LOAD_IMG)? 
        MAX_CHANNELS : { s00_axis_tuser[2*ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : ADDR_WIDTH + NUM_CHANNELS_WIDTH] , s00_axis_tuser[ ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : NUM_CHANNELS_WIDTH] , s00_axis_tuser[NUM_CHANNELS_WIDTH -1 : 0] } ; // use for channel number 

    // sram_ker signals
    assign s00_axis_tready = s00_axis_tvalid;
    reg we1_ker1_reg;
    assign { ker_row , ker_col , num_channels1_ker_i } = (s00_axis_tlast && state == LOAD_KER)? 
        MAX_CHANNELS : { s00_axis_tuser[2*ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : ADDR_WIDTH + NUM_CHANNELS_WIDTH] , s00_axis_tuser[ ADDR_WIDTH + NUM_CHANNELS_WIDTH -1 : NUM_CHANNELS_WIDTH] , s00_axis_tuser[NUM_CHANNELS_WIDTH -1 : 0] } ; // use for channel number 
    
    // output row and col
    wire [ADDR_WIDTH-1:0] out_row, out_col;
    assign out_row = img_row_reg - ker_row_reg + 1;
    assign out_col = img_col_reg - ker_col_reg + 1;

    // convolution col and row index
    reg [MAX_ADDR_WIDTH-1:0] conv_row;
    reg [MAX_ADDR_WIDTH-1:0] conv_col;

    

// ****************************************************************************************************
    reg [ADDR_WIDTH-1:0] read_idx;  
    reg read_sram_enable;  
    reg signed [2*C_AXIS_TDATA_WIDTH-1:0] axi4_data_out;  

    // sram input and output signals

    // assign axi4_data_out = data_out[MAX_DATA_WIDTH*ELEM0_SRAM_IDX +: 2*C_AXIS_MDATA_WIDTH];  
    always @(*)begin
        if(axi4_data_out !== data_out[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH])begin
            axi4_data_out = data_out[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH];
        end
    end

    always @(*)begin
        if(m00_axis_tdata !== data_out[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH])begin
            m00_axis_tdata = data_out[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH];
        end
    end
    /***** AXI4-Stream 傳輸資料 *****/
    reg stop = 0;
    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            stop <= 0;
        end else if (read_sram_enable && m00_axis_tready && !stop) begin
            if (read_idx == (out_col * out_row- 1)) begin
                stop <= 1;
            end
        end 
    end

    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            m00_axis_tlast <= 0;
        end else if (read_sram_enable && m00_axis_tready && !stop) begin
            if (read_idx == (out_col * out_row- 2)) begin
                m00_axis_tlast <= 1;
            end else begin
                m00_axis_tlast <= 0;
            end
        end
    end

    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            m00_axis_tvalid <= 0;
        end else if (read_sram_enable && m00_axis_tready && !stop) begin
            if (read_idx == (out_col * out_row- 1)) begin
                m00_axis_tvalid <= 0;  // stop
            end else begin
                m00_axis_tvalid <= 1;
            end
        end else begin
            m00_axis_tvalid <= 0;  // 如果 AXI 不 ready，暫停傳輸
        end
    end

    always @(posedge m00_axis_aclk) begin
        if (!m00_axis_aresetn) begin
            read_idx <= 0;
        end else if (read_sram_enable && m00_axis_tready && !stop) begin
            if (read_idx == (out_col * out_row- 1)) begin
                read_idx <= 0;  // reset
            end else begin
                read_idx <= read_idx + 1;
            end
        end 
    end


    /***** 控制讀取 SRAM[0] 的啟動條件 *****/
    always @(posedge s00_axis_aclk) begin
        if (!s00_axis_aresetn) begin
            read_sram_enable <= 0;
        end else if (m00_axis_tready) begin
            read_sram_enable <= 1;  // 啟用 SRAM[0] 的讀取
        end else if (m00_axis_tlast) begin
            read_sram_enable <= 0;  // 傳輸結束，停止讀取
        end
    end



// ****************************************************************************************************

    // sram_img and sram_ker port2 for enable read sram
    always @(*)begin
        we = {NUM_SRAMS{1'b0}};
        // if(s00_axis_tvalid & s00_axis_tready & (state==LOAD_IMG))begin
        if((s00_axis_tvalid & s00_axis_tready && (ST_state==ST_IMG)))begin
            we[GEMM0_SRAM_IDX] = 1'b1;
        end
        // if(s00_axis_tvalid & s00_axis_tready & (state==LOAD_KER))begin
        if((s00_axis_tvalid & s00_axis_tready && (ST_state==ST_KER)))begin
            we[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(read_sram_enable)begin
            we[ELEM0_SRAM_IDX] = 1'b0;
        end else if(mac_valid_out)begin
            we[ELEM0_SRAM_IDX] = 1'b1;
        end
    end

    always @(*)begin
        en = {NUM_SRAMS{1'b0}};
        if(we[GEMM0_SRAM_IDX])begin
            en[GEMM0_SRAM_IDX] = 1'b1;
        end
        if(we[GEMM1_SRAM_IDX])begin
            en[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(state == COMPUTE_CONV0)begin
            en[GEMM0_SRAM_IDX] = 1'b1;
            en[GEMM1_SRAM_IDX] = 1'b1;
        end
        if(mac_valid_out || read_sram_enable)begin
            en[ELEM0_SRAM_IDX] = 1'b1;
        end
    end

    // sram input address
    reg [ADDR_WIDTH-1: 0] for_conv_row, for_conv_col;

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            for_conv_col <= 0;
        end else if( state == COMPUTE_CONV0 && for_conv_col < ker_col_reg-1)begin
            for_conv_col <= for_conv_col + 1;
        end else if( state == COMPUTE_CONV0 && for_conv_col == ker_col_reg-1)begin
            for_conv_col <= 0;
        end else if (state == COMPUTE_CONV1) begin
            for_conv_col <= 0;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            for_conv_row <= 0;
        end else if( state == COMPUTE_CONV0 && for_conv_col == ker_col_reg-1)begin
            for_conv_row <= for_conv_row + 1;
        end else if( state == COMPUTE_CONV1)begin
            for_conv_row <= 0;
        end
    end

    always @(*) begin
        addr = {NUM_SRAMS * MAX_ADDR_WIDTH{1'b0}};  // 初始化為 0

        if(en[GEMM0_SRAM_IDX] && state == COMPUTE_CONV0) begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = (conv_row + for_conv_row) * img_col_reg + conv_col + for_conv_col;
        end else if(en[GEMM0_SRAM_IDX]) begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_img;
        end

        if(en[GEMM1_SRAM_IDX] && state == COMPUTE_CONV0) begin
            addr[GEMM1_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = for_conv_row * ker_col_reg + for_conv_col;
        end else if(en[GEMM1_SRAM_IDX]) begin
            addr[GEMM1_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_ker;
        end

        if(en[ELEM0_SRAM_IDX] && read_sram_enable)begin
            addr[ELEM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = read_idx;
        end else if(en[ELEM0_SRAM_IDX]) begin
            addr[ELEM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = idx1_out;
        end 
        
        // ********************** MODIFY
        // if(m00_axis_tready && m00_axis_tvalid)begin
        if(read_sram_enable)begin
            addr[GEMM0_SRAM_IDX * MAX_ADDR_WIDTH +: MAX_ADDR_WIDTH] = read_idx;
        end
        // ********************** MODIFY
    end
    // sram input data
    always @(*)begin
        data_in = {NUM_SRAMS * MAX_DATA_WIDTH{1'b0}};
        if(we[GEMM0_SRAM_IDX])begin
            data_in[GEMM0_SRAM_IDX * MAX_DATA_WIDTH  +: C_AXIS_TDATA_WIDTH] =  s00_axis_tdata;
        end
        if(we[GEMM1_SRAM_IDX])begin
            data_in[GEMM1_SRAM_IDX * MAX_DATA_WIDTH +: C_AXIS_TDATA_WIDTH] =  s00_axis_tdata;
        end
        if(mac_valid_out)begin
            data_in[ELEM0_SRAM_IDX * MAX_DATA_WIDTH +: 2*C_AXIS_TDATA_WIDTH] = mac_out;
        end
    end

    /* store img_row img_col */
    always @(posedge s00_axis_aclk)begin
        if(s00_axis_tlast && state == LOAD_IMG)begin
            img_row_reg <= img_row;
            img_col_reg <= img_col;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(s00_axis_tlast && state == LOAD_KER)begin
            ker_row_reg <= ker_row;
            ker_col_reg <= ker_col;
        end
    end
    
    /**** control input data signals ****/
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            last_data_reg <= 0;
        end else begin
            last_data_reg <= s00_axis_tlast;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            last_data <= 0;
        end else begin
            last_data <= last_data_reg;
            if(last_data_reg)begin
                ST_state <= ST_state + 1;
            end 
        end
    end

    /***** FSM control *****/
    always @(*)begin
        case(state)
            IDLE: begin
                if(s00_axis_tvalid && s00_axis_tready)begin
                    next_state = LOAD_IMG;
                end
            end
            LOAD_IMG: begin
                if(last_data)begin
                    next_state = LOAD_KER;
                end
            end
            LOAD_KER: begin
                if(last_data)begin
                    next_state = COMPUTE_CONV0;
                end
            end
            // TODO: COMPUTE_CONV and WRITE_OUTPUT are not implemented yet
            COMPUTE_CONV0: begin
                // next_state = COMPUTE_CONV;
                if(conv_row == out_row)begin
                    next_state = WRITE_OUTPUT;
                end else if( (for_conv_col + ker_col_reg*for_conv_row) < ker_col_reg * ker_row_reg -1)begin
                    next_state = COMPUTE_CONV0;
                end else begin
                    next_state = COMPUTE_CONV1;
                end
            end
            COMPUTE_CONV1: begin
                    next_state = COMPUTE_CONV0;
            end
            WRITE_OUTPUT: begin
                if(read_idx < out_row * out_col)begin
                    next_state = WRITE_OUTPUT;
                end else begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    /***** FSM control *****/

    /***** index control *****/
    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn) begin
            idx1_img <= 0;
        end else if(we[GEMM0_SRAM_IDX]  )begin
            idx1_img <= idx1_img + 1;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn) begin
            idx1_ker <= 0;
        end else if(we[GEMM1_SRAM_IDX])begin
            idx1_ker <= idx1_ker + 1;
        end
    end

    /***** index control *****/

    integer row,col,m,n,j;
    /***** mac unit signals control *****/
    assign num_macs_i = (state == COMPUTE_CONV1)? ker_row_reg * ker_col_reg : 0;
    assign mac_valid_in = (state == COMPUTE_CONV1)? 1 : 0;

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            conv_col <= 0;
        end else if (conv_col == out_col-1 && for_conv_row==ker_row_reg)begin
            conv_col <= 0;
        end else if(state == COMPUTE_CONV1)begin
            conv_col <= conv_col + 1;
        end
    end

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            conv_row <= 0;
        end else if(conv_col == out_col-1 && for_conv_row==ker_row_reg)begin
            conv_row <= conv_row + 1;
        end
    end

    always @(*)begin
        if(state == COMPUTE_CONV0 || for_conv_col + for_conv_row * ker_col_reg <= ker_col_reg * ker_row_reg) begin
            data_mac_i[(for_conv_row*ker_col_reg + for_conv_col -1)*C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] = data_out[GEMM0_SRAM_IDX * MAX_DATA_WIDTH +: C_AXIS_TDATA_WIDTH];
        end
    end

    always @(*)begin
        if(state == COMPUTE_CONV0 || for_conv_col + for_conv_row * ker_col_reg <= ker_col_reg * ker_row_reg) begin
            weight_mac_i[(for_conv_row*ker_col_reg + for_conv_col -1)*C_AXIS_TDATA_WIDTH +: C_AXIS_TDATA_WIDTH] = data_out[GEMM1_SRAM_IDX * MAX_DATA_WIDTH +: C_AXIS_TDATA_WIDTH];
        end
    end


    /***** sram_output_idx *****/

    always @(posedge s00_axis_aclk)begin
        if(!s00_axis_aresetn)begin
            idx1_out <= 0;
        end else if(mac_valid_out)begin
            idx1_out <= idx1_out + 1'b1;
        end
    end

    /***** sram_output_idx *****/

    multi_sram multi_sram_gen(
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .en(en),
        .we(we),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

    mac #
    (
        .MAX_MACS(MAX_MACS)
    )
    mac_gen(
        .clk(s00_axis_aclk),
        .rst(s00_axis_aresetn),
        .num_macs_i(num_macs_i),
        .valid_in(mac_valid_in),
        .data(data_mac_i),
        .weight(weight_mac_i),
        .mac_out(mac_out),
        .valid_out(mac_valid_out)
    );
    

endmodule
