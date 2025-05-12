// -----------------------------------------------------------------------------
// op_decoder: Operation Decoder and Sequencer
// 4'b0000: No operation -> idle
// 4'b0001: Conv
// 4'b0010: Fc
// 4'b0011: Exp
// 4'b0100: Reciprocal
// 4'b0101: ADD
// 4'b0110: SUB
// 4'b0111: MUL
// SUB: data-weight, 如果是其他engine流向他的data直接放在後面, 也就是weight的位置
//      至於如果是第一個op, 則是compiler控制, data是哪一個以及weight是哪一個sram取得
// 各個engine先delay一個cycle? 因為需要等broadcast那邊判斷完
// 為什麼各個data_in要多等一cycle? 因為要配合weight有可能broadcast情形
// 為什麼op_done_reg要多等一cycle? 因為也是要配合weight可能有broadcast情形
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`include "params.vh"


module op_decoder #
(
    parameter MAX_VECTOR_SIZE = 8,
    parameter DATA_WIDTH = 64
)
(
    input clk,
    input wire [15:0] op,
    input valid_in,
    input rst,
    input init,
    // CONV
    input wire conv_valid_out,
    input wire [DATA_WIDTH-1:0] conv_data_out,
    output reg [DATA_WIDTH-1:0] conv_data_in,
    output reg conv_en,
    // Fc
    input wire fc_valid_out,
    input wire [DATA_WIDTH-1:0] fc_data_out,
    output reg [DATA_WIDTH-1:0] fc_data_in,
    output reg fc_en,
    // Exp
    input wire exp_valid_out,
    input wire [DATA_WIDTH-1:0] exp_data_out,
    output reg [DATA_WIDTH-1:0] exp_data_in,
    output reg exp_en,
    // Reciprocal
    input wire reciprocal_valid_out,
    input wire [DATA_WIDTH-1:0] reciprocal_data_out,
    output reg [DATA_WIDTH-1:0] reciprocal_data_in,
    output reg reciprocal_en,
    // ADD
    input wire add_valid_out,
    input wire [DATA_WIDTH-1:0] add_data_out,
    output reg [DATA_WIDTH-1:0] add_data_in,
    output reg [DATA_WIDTH-1:0] add_weight_in,
    output reg add_en,
    // SUB
    input wire sub_valid_out,
    input wire [DATA_WIDTH-1:0] sub_data_out,
    output reg [DATA_WIDTH-1:0] sub_data_in,
    output reg [DATA_WIDTH-1:0] sub_weight_in,
    output reg sub_en,
    // MUL
    input wire mul_valid_out,
    input wire [DATA_WIDTH-1:0] mul_data_out,
    output reg [DATA_WIDTH-1:0] mul_data_in,
    output reg [DATA_WIDTH-1:0] mul_weight_in,
    output reg mul_en,
    // the signals for storing the output in sram
    output reg store_to_sram_en,
    output wire [DATA_WIDTH-1:0] store_to_sram_data,
    // op starts taking data signals
    output reg op0_data_sram_en,
    output reg op1_data_sram_en,
    output reg op2_data_sram_en,
    output reg op3_data_sram_en,
    output wire [MAX_ADDR_WIDTH-1:0] op0_weight_addr_o,
    output wire [MAX_ADDR_WIDTH-1:0] op0_data_addr_o,
    output wire [MAX_ADDR_WIDTH-1:0] op1_weight_addr_o,
    output wire [MAX_ADDR_WIDTH-1:0] op2_weight_addr_o,
    output wire [MAX_ADDR_WIDTH-1:0] op3_weight_addr_o,
    // weight data in
    input [DATA_WIDTH-1:0] op0_data_sram_data_i,
    input [DATA_WIDTH-1:0] op0_weight_sram_data_i,
    input [DATA_WIDTH-1:0] op1_weight_sram_data_i,
    input [DATA_WIDTH-1:0] op2_weight_sram_data_i,
    input [DATA_WIDTH-1:0] op3_weight_sram_data_i,
    // number of each op
    input wire [3:0] num_groups,
    // op0,1,2,3 data counts
    input wire [MAX_ADDR_WIDTH-1:0] op0_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op1_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op2_data_counts,
    input wire [MAX_ADDR_WIDTH-1:0] op3_data_counts,
    // output counts
    output wire [MAX_ADDR_WIDTH-1:0] op_total_data_counts,
    output wire [MAX_ADDR_WIDTH-1:0] expected_total_data_counts
);
    reg [15:0] op_reg;
    always @(posedge clk) begin
        if(!rst) begin
            op_reg <= 0;
        end else begin
            op_reg <= op;
        end
    end
    wire [3:0] op0, op1, op2, op3;
    assign op0 = op_reg[3:0];
    assign op1 = op_reg[7:4];
    assign op2 = op_reg[11:8];
    assign op3 = op_reg[15:12];

    reg [MAX_ADDR_WIDTH-1:0] op0_data_counts_reg, op1_data_counts_reg, op2_data_counts_reg, op3_data_counts_reg;
    always @(posedge clk) begin
        if(!rst) begin
            op0_data_counts_reg <= 0;
        end else begin
            op0_data_counts_reg <= op0_data_counts;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op1_data_counts_reg <= 0;
        end else begin
            op1_data_counts_reg <= op1_data_counts;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op2_data_counts_reg <= 0;
        end else begin
            op2_data_counts_reg <= op2_data_counts;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op3_data_counts_reg <= 0;
        end else begin
            op3_data_counts_reg <= op3_data_counts;
        end
    end
    reg valid_in_reg;
    reg [MAX_ADDR_WIDTH-1:0] op0_counter, op1_counter, op2_counter, op3_counter;
    reg [MAX_ADDR_WIDTH-1:0] op0_weight_counter, op1_weight_counter, op2_weight_counter, op3_weight_counter;
    wire [DATA_WIDTH-1:0] op0_data_out, op1_data_out, op2_data_out, op3_data_out;
    reg [DATA_WIDTH-1:0] op0_data_out_reg, op1_data_out_reg, op2_data_out_reg, op3_data_out_reg;
    reg [DATA_WIDTH-1:0] op0_data_out_reg_d, op1_data_out_reg_d, op2_data_out_reg_d, op3_data_out_reg_d;
    reg op0_done_reg, op1_done_reg, op2_done_reg, op3_done_reg;
    reg op0_done_reg_d, op1_done_reg_d, op2_done_reg_d, op3_done_reg_d;
    wire op0_done, op1_done, op2_done, op3_done;
    reg [MAX_ADDR_WIDTH-1:0] op0_elementwise_counter;

    // en delay, 因為前面broadcast有delay, 所以en跟data都要delay
    reg conv_en_delay, fc_en_delay, exp_en_delay, reciprocal_en_delay, add_en_delay, sub_en_delay, mul_en_delay;

    always @(posedge clk) begin
        if(!rst) begin
            valid_in_reg <= 0;
        end else begin
            valid_in_reg <= valid_in;
        end
    end
    
    // 2-stage to store op0,1,2,3 done reg
    
    always @(posedge clk) begin
        if(!rst) begin
            op0_done_reg <= 0;
        end else begin
            op0_done_reg <= op0_done;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op1_done_reg <= 0;
        end else begin
            op1_done_reg <= op1_done;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op2_done_reg <= 0;
        end else begin
            op2_done_reg <= op2_done;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op3_done_reg <= 0;
        end else begin
            op3_done_reg <= op3_done;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op0_done_reg_d <= 0;
        end else begin
            op0_done_reg_d <= op0_done_reg;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op1_done_reg_d <= 0;
        end else begin
            op1_done_reg_d <= op1_done_reg;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op2_done_reg_d <= 0;
        end else begin
            op2_done_reg_d <= op2_done_reg;
        end
    end
    always @(posedge clk) begin
        if(!rst) begin
            op3_done_reg_d <= 0;
        end else begin
            op3_done_reg_d <= op3_done_reg;
        end
    end
    // ---------------------------------------------------

    assign op0_done = (op0 == 4'b0001) ? conv_valid_out :
                      (op0 == 4'b0010) ? fc_valid_out :
                      (op0 == 4'b0011) ? exp_valid_out :
                      (op0 == 4'b0100) ? reciprocal_valid_out :
                      (op0 == 4'b0101) ? add_valid_out :
                      (op0 == 4'b0110) ? sub_valid_out :
                      (op0 == 4'b0111) ? mul_valid_out : 1'b0;
    assign op1_done = (op1 == 4'b0001) ? conv_valid_out :
                      (op1 == 4'b0010) ? fc_valid_out :
                      (op1 == 4'b0011) ? exp_valid_out :
                      (op1 == 4'b0100) ? reciprocal_valid_out :
                      (op1 == 4'b0101) ? add_valid_out :
                      (op1 == 4'b0110) ? sub_valid_out :
                      (op1 == 4'b0111) ? mul_valid_out : 1'b0;
    assign op2_done = (op2 == 4'b0001) ? conv_valid_out :
                      (op2 == 4'b0010) ? fc_valid_out :
                      (op2 == 4'b0011) ? exp_valid_out :
                      (op2 == 4'b0100) ? reciprocal_valid_out :
                      (op2 == 4'b0101) ? add_valid_out :
                      (op2 == 4'b0110) ? sub_valid_out :
                      (op2 == 4'b0111) ? mul_valid_out : 1'b0;
    assign op3_done = (op3 == 4'b0001) ? conv_valid_out :
                      (op3 == 4'b0010) ? fc_valid_out :
                      (op3 == 4'b0011) ? exp_valid_out :
                      (op3 == 4'b0100) ? reciprocal_valid_out :
                      (op3 == 4'b0101) ? add_valid_out :
                      (op3 == 4'b0110) ? sub_valid_out :
                      (op3 == 4'b0111) ? mul_valid_out : 1'b0;  
    // data output selection for each op stage  
    assign op0_data_out = (op0 == 4'b0001) ? conv_data_out :
                          (op0 == 4'b0010) ? fc_data_out :
                          (op0 == 4'b0011) ? exp_data_out :
                          (op0 == 4'b0100) ? reciprocal_data_out :
                          (op0 == 4'b0101) ? add_data_out :
                          (op0 == 4'b0110) ? sub_data_out :
                          (op0 == 4'b0111) ? mul_data_out : 0;
    assign op1_data_out = (op1 == 4'b0001) ? conv_data_out :
                          (op1 == 4'b0010) ? fc_data_out :
                          (op1 == 4'b0011) ? exp_data_out :
                          (op1 == 4'b0100) ? reciprocal_data_out :
                          (op1 == 4'b0101) ? add_data_out :
                          (op1 == 4'b0110) ? sub_data_out :
                          (op1 == 4'b0111) ? mul_data_out : 0;
    assign op2_data_out = (op2 == 4'b0001) ? conv_data_out :
                          (op2 == 4'b0010) ? fc_data_out :
                          (op2 == 4'b0011) ? exp_data_out :
                          (op2 == 4'b0100) ? reciprocal_data_out :
                          (op2 == 4'b0101) ? add_data_out :
                          (op2 == 4'b0110) ? sub_data_out :
                          (op2 == 4'b0111) ? mul_data_out : 0;
    assign op3_data_out = (op3 == 4'b0001) ? conv_data_out :
                          (op3 == 4'b0010) ? fc_data_out :
                          (op3 == 4'b0011) ? exp_data_out :
                          (op3 == 4'b0100) ? reciprocal_data_out :
                          (op3 == 4'b0101) ? add_data_out :
                          (op3 == 4'b0110) ? sub_data_out :
                          (op3 == 4'b0111) ? mul_data_out : 0;

    // 2-stage to store data for data_out from each engine
    // ---------------------------------------------------
    always @(posedge clk) begin
        if(!rst) begin
            op0_data_out_reg <= 0;
        end else begin
            op0_data_out_reg <= op0_data_out;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op1_data_out_reg <= 0;
        end else begin
            op1_data_out_reg <= op1_data_out;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op2_data_out_reg <= 0;
        end else begin
            op2_data_out_reg <= op2_data_out;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op3_data_out_reg <= 0;
        end else begin
            op3_data_out_reg <= op3_data_out;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op0_data_out_reg_d <= 0;
        end else begin
            op0_data_out_reg_d <= op0_data_out_reg;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op1_data_out_reg_d <= 0;
        end else begin
            op1_data_out_reg_d <= op1_data_out_reg;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op2_data_out_reg_d <= 0;
        end else begin
            op2_data_out_reg_d <= op2_data_out_reg;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op3_data_out_reg_d <= 0;
        end else begin
            op3_data_out_reg_d <= op3_data_out_reg;
        end
    end
    // ---------------------------------------------------
    
    // signals for sram & output data counts
    always @(posedge clk) begin
        if(!rst) begin
            store_to_sram_en <= 0;
        end else if(init) begin
            store_to_sram_en <= 0; 
        end else begin
            store_to_sram_en <= (op3_done)? 1'b1 : 
                                  (op2_done && op3 == 4'b0000)? 1'b1 :
                                  (op1_done && op2 == 4'b0000)? 1'b1 :
                                  (op0_done && op1 == 4'b0000)? 1'b1 : 1'b0;
        end
    end
    // assign store_to_sram_en = (op3_done_reg)? 1'b1 : 
    //                           (op2_done_reg && op3 == 4'b0000)? 1'b1 :
    //                           (op1_done_reg && op2 == 4'b0000)? 1'b1 :
    //                           (op0_done_reg && op1 == 4'b0000)? 1'b1 : 1'b0;
    assign store_to_sram_data = (op3_done_reg)? op3_data_out_reg : 
                                (op2_done_reg && op3 == 4'b0000)? op2_data_out_reg :
                                (op1_done_reg && op2 == 4'b0000)? op1_data_out_reg :
                                (op0_done_reg && op1 == 4'b0000)? op0_data_out_reg : 0;
    assign op_total_data_counts = (op1 == 4'b0000)? op0_counter : 
                                  (op2 == 4'b0000)? op1_counter :
                                  (op3 == 4'b0000)? op2_counter : op3_counter;
    assign expected_total_data_counts = (op1 == 4'b0000)? op0_data_counts_reg : 
                                        (op2 == 4'b0000)? op1_data_counts_reg :
                                        (op3 == 4'b0000)? op2_data_counts_reg : op3_data_counts_reg;
    //--------------------------------------------------------------------------
    // Engine Enable signals independent of the operation
    //--------------------------------------------------------------------------

    // conv_en
    always @(posedge clk) begin
        if (!rst)
            conv_en_delay <= 0;
        else if (init)
            conv_en_delay <= 0;
        else
            conv_en_delay <= ((valid_in_reg && (op0 == 4'b0001) && (op0_counter < op0_data_counts_reg)) ||
                        (op0_done_reg && (op1 == 4'b0001) && (op1_counter < op1_data_counts_reg)) ||
                        (op1_done_reg && (op2 == 4'b0001) && (op2_counter < op2_data_counts_reg)) ||
                        (op2_done_reg && (op3 == 4'b0001) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            conv_en <= 0;
        end else begin
            conv_en <= conv_en_delay;
        end
    end

    // fc_en
    always @(posedge clk) begin
        if (!rst)
            fc_en_delay <= 0;
        else if(init)
            fc_en_delay <= 0;
        else
            fc_en_delay <= ((valid_in_reg && (op0 == 4'b0010) && (op0_counter < op0_data_counts_reg)) ||
                      (op0_done_reg && (op1 == 4'b0010) && (op1_counter < op1_data_counts_reg)) ||
                      (op1_done_reg && (op2 == 4'b0010) && (op2_counter < op2_data_counts_reg)) ||
                      (op2_done_reg && (op3 == 4'b0010) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            fc_en <= 0;
        end else begin
            fc_en <= fc_en_delay;
        end
    end

    // exp_en
    always @(posedge clk) begin
        if (!rst)
            exp_en_delay <= 0;
        else if(init)
            exp_en_delay <= 0;
        else begin
            exp_en_delay <= ((valid_in_reg && (op0 == 4'b0011) && (op0_counter < op0_data_counts_reg)) ||
                       (op0_done_reg && (op1 == 4'b0011) && (op1_counter < op1_data_counts_reg)) ||
                       (op1_done_reg && (op2 == 4'b0011) && (op2_counter < op2_data_counts_reg)) ||
                       (op2_done_reg && (op3 == 4'b0011) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
                    //    $display("op0_done_reg = %d, op0_done = %d, exp_en -> op1 = %h, op1_counter = %d, exp_en = %d",op0_done_reg,op0_done, op1, op1_counter, exp_en);
                    //    $display("op1_done_reg = %d, op1_done = %d", op1_done_reg,op1_done);
                    //    $display("conv_valid_out = %d, fc_valid_out = %d, exp_valid_out = %d, reciprocal_valid_out = %d, add_valid_out = %d, sub_valid_out = %d, mul_valid_out = %d", conv_valid_out, fc_valid_out, exp_valid_out, reciprocal_valid_out, add_valid_out, sub_valid_out, mul_valid_out); 
                    //    $display("op0_counter = %d, op0_data_counts = %d", op0_counter, op0_data_counts);
                    // $display("store_to_sram_en = %d, store_to_sram_data = %h", store_to_sram_en, store_to_sram_data);
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            exp_en <= 0;
        end else begin
            exp_en <= exp_en_delay;
        end
    end

    // reciprocal_en
    always @(posedge clk) begin
        if (!rst)
            reciprocal_en_delay <= 0;
        else if(init)
            reciprocal_en_delay <= 0;
        else
            reciprocal_en_delay <= ((valid_in_reg && (op0 == 4'b0100) && (op0_counter < op0_data_counts_reg)) ||
                              (op0_done_reg && (op1 == 4'b0100) && (op1_counter < op1_data_counts_reg)) ||
                              (op1_done_reg && (op2 == 4'b0100) && (op2_counter < op2_data_counts_reg)) ||
                              (op2_done_reg && (op3 == 4'b0100) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            reciprocal_en <= 0;
        end else begin
            reciprocal_en <= reciprocal_en_delay;
        end
    end

    // add_en
    always @(posedge clk) begin
        if (!rst)
            add_en_delay <= 0;
        else if(init)
            add_en_delay <= 0;
        else
            add_en_delay <= ((valid_in_reg && (op0 == 4'b0101) && (op0_counter < op0_data_counts_reg)) ||
                       (op0_done_reg && (op1 == 4'b0101) && (op1_counter < op1_data_counts_reg)) ||
                       (op1_done_reg && (op2 == 4'b0101) && (op2_counter < op2_data_counts_reg)) ||
                       (op2_done_reg && (op3 == 4'b0101) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            add_en <= 0;
        end else begin
            add_en <= add_en_delay;
        end
    end

    // sub_en
    always @(posedge clk) begin
        if (!rst)
            sub_en_delay <= 0;
        else if(init)
            sub_en_delay <= 0;
        else
            sub_en_delay <= ((valid_in_reg && (op0 == 4'b0110) && (op0_counter < op0_data_counts_reg)) ||
                       (op0_done_reg && (op1 == 4'b0110) && (op1_counter < op1_data_counts_reg)) ||
                       (op1_done_reg && (op2 == 4'b0110) && (op2_counter < op2_data_counts_reg)) ||
                       (op2_done_reg && (op3 == 4'b0110) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            sub_en <= 0;
        end else begin
            sub_en <= sub_en_delay;
        end
    end

    // mul_en
    always @(posedge clk) begin
        if (!rst)
            mul_en_delay <= 0;
        else if(init)
            mul_en_delay <= 0;
        else
            mul_en_delay <= ((valid_in_reg && (op0 == 4'b0111) && (op0_counter < op0_data_counts_reg)) ||
                       (op0_done_reg && (op1 == 4'b0111) && (op1_counter < op1_data_counts_reg)) ||
                       (op1_done_reg && (op2 == 4'b0111) && (op2_counter < op2_data_counts_reg)) ||
                       (op2_done_reg && (op3 == 4'b0111) && (op3_counter < op3_data_counts_reg))) ? 1 : 0;
    end

    always @(posedge clk) begin
        if(!rst) begin
            mul_en <= 0;
        end else begin
            mul_en <= mul_en_delay;
        end
    end

    // op1,2,3 data transfer
    always @(posedge clk) begin
        if(!rst) begin
            conv_data_in       <= 0;
            fc_data_in         <= 0;
            exp_data_in        <= 0;
            reciprocal_data_in <= 0;
            add_data_in        <= 0;
            sub_weight_in        <= 0;
            mul_data_in        <= 0;
        end
        if(op0 != 4'b0001 && op0 != 4'b0010) begin
            case(op0) 
                4'b0101: add_data_in        <= op0_data_sram_data_i;        // ADD
                4'b0110: sub_weight_in        <= op0_data_sram_data_i;        // SUB
                4'b0111: mul_data_in        <= op0_data_sram_data_i;        // MUL
                default: ; // Do nothing
            endcase
        end 
        if(op0_done_reg_d) begin
            case(op1)
                4'b0001: conv_data_in       <= op0_data_out_reg_d;        // Conv
                4'b0010: fc_data_in         <= op0_data_out_reg_d;        // Fc
                4'b0011: exp_data_in        <= op0_data_out_reg_d;        // Exp
                4'b0100: reciprocal_data_in <= op0_data_out_reg_d;        // Reciprocal
                4'b0101: add_data_in        <= op0_data_out_reg_d;        // ADD
                4'b0110: sub_weight_in        <= op0_data_out_reg_d;        // SUB
                4'b0111: mul_data_in        <= op0_data_out_reg_d;        // MUL
                default: ; // Do nothing
            endcase
        end 
        if(op1_done_reg_d) begin
            case(op2)
                4'b0001: conv_data_in       <= op1_data_out_reg_d;        // Conv
                4'b0010: fc_data_in         <= op1_data_out_reg_d;        // Fc
                4'b0011: exp_data_in        <= op1_data_out_reg_d;        // Exp
                4'b0100: reciprocal_data_in <= op1_data_out_reg_d;        // Reciprocal
                4'b0101: add_data_in        <= op1_data_out_reg_d;        // ADD
                4'b0110: sub_weight_in        <= op1_data_out_reg_d;        // SUB
                4'b0111: mul_data_in        <= op1_data_out_reg_d;        // MUL
                default: ; // Do nothing
            endcase
        end 
        if(op2_done_reg_d) begin
            case(op3)
                4'b0001: conv_data_in       <= op2_data_out_reg_d;        // Conv
                4'b0010: fc_data_in         <= op2_data_out_reg_d;        // Fc
                4'b0011: exp_data_in        <= op2_data_out_reg_d;        // Exp
                4'b0100: reciprocal_data_in <= op2_data_out_reg_d;        // Reciprocal
                4'b0101: add_data_in        <= op2_data_out_reg_d;        // ADD
                4'b0110: sub_weight_in        <= op2_data_out_reg_d;        // SUB
                4'b0111: mul_data_in        <= op2_data_out_reg_d;        // MUL
                default: ; // Do nothing
            endcase
        end
    end

    // op0,1,2,3 weight transfer
    always @(posedge clk) begin
        if(!rst) begin
            add_weight_in <= 0;
            sub_data_in <= 0;
            mul_weight_in <= 0;
        end 
        if(valid_in_reg) begin
            case(op0)
                4'b0101: add_weight_in <= op0_weight_sram_data_i;
                4'b0110: sub_data_in <= op0_weight_sram_data_i;
                4'b0111: mul_weight_in <= op0_weight_sram_data_i;
                default: ; // Do nothing
            endcase
        end 
        if(op0_done_reg_d) begin
            case(op1)
                4'b0101: add_weight_in <= op1_weight_sram_data_i;
                4'b0110: sub_data_in <= op1_weight_sram_data_i;
                4'b0111: mul_weight_in <= op1_weight_sram_data_i;
                default: ; // Do nothing
            endcase
        end 
        if(op1_done_reg_d) begin
            case(op2)
                4'b0101: add_weight_in <= op2_weight_sram_data_i;
                4'b0110: sub_data_in <= op2_weight_sram_data_i;
                4'b0111: mul_weight_in <= op2_weight_sram_data_i;
                default: ; // Do nothing
            endcase
        end 
        if(op2_done_reg_d) begin
            case(op3)
                4'b0101: add_weight_in <= op3_weight_sram_data_i;
                4'b0110: sub_data_in <= op3_weight_sram_data_i;
                4'b0111: mul_weight_in <= op3_weight_sram_data_i;
                default: ; // Do nothing
            endcase
        end
    end

    // op0,1,2,3 enable for SRAM data read, modify it to be the combinational because of one cycle for en, and one cycle for data
    always @(*) begin
        op0_data_sram_en = (valid_in && op0 != 4'b0000 && op0 != 4'b0001 && op0 != 4'b0010) ? 1 : 0;
        op1_data_sram_en = (op0_done && op1 != 4'b0000) ? 1 : 0;
        op2_data_sram_en = (op1_done && op2 != 4'b0000) ? 1 : 0;
        op3_data_sram_en = (op2_done && op3 != 4'b0000) ? 1 : 0;
    end
    // always @(posedge clk) begin
    //     if(!rst)begin
    //         op0_data_sram_en <= 0;
    //     end else if(valid_in && op0 != 4'b0000) begin
    //         op0_data_sram_en <= 1;
    //     end
    // end

    // always @(posedge clk)begin
    //     if(!rst) begin
    //         op1_data_sram_en <= 0;
    //     end else if(op0_done && op1 != 4'b0000) begin
    //         op1_data_sram_en <= 1;
    //     end
    // end

    // always @(posedge clk)begin
    //     if(!rst) begin
    //         op2_data_sram_en <= 0;
    //     end else if(op1_done && op2 != 4'b0000) begin
    //         op2_data_sram_en <= 1;
    //     end
    // end

    // always @(posedge clk)begin
    //     if(!rst) begin
    //         op3_data_sram_en <= 0;
    //     end else if(op2_done && op3 != 4'b0000) begin
    //         op3_data_sram_en <= 1;
    //     end
    // end

    // op weight address
    assign op0_data_addr_o = op0_weight_counter;
    assign op0_weight_addr_o = op0_weight_counter;
    assign op1_weight_addr_o = op1_weight_counter;
    assign op2_weight_addr_o = op2_weight_counter;
    assign op3_weight_addr_o = op3_weight_counter;

    // counter update
    always @(posedge clk) begin
        if(!rst) begin
            op0_counter <= 0;
        end else if(init) begin
            op0_counter <= 0;
        end else if(op0_done_reg_d) begin
            op0_counter <= op0_counter +  num_groups;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op1_counter <= 0;
        end else if(init) begin
            op1_counter <= 0;
        end else if(op1_done_reg_d) begin
            op1_counter <= op1_counter +  num_groups;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op2_counter <= 0;
        end else if(init) begin
            op2_counter <= 0;
        end else if(op2_done_reg_d) begin
            op2_counter <= op2_counter +  num_groups;
        end
    end

    always @(posedge clk) begin
        if(!rst) begin
            op3_counter <= 0;
        end else if(init) begin
            op3_counter <= 0;
        end else if(op3_done_reg_d) begin
            op3_counter <= op3_counter +  num_groups;
        end
    end

    // ================= Weight Index Counter Update =================
    // 針對 add/sub/mul，當 op完成一個 group 的運算後，對應的 weight counter累加 num_groups
    always @(posedge clk) begin
        if (!rst) begin
            op0_weight_counter <= 0;
        end else if(init) begin
            op0_weight_counter <= 0; 
        end else if (op0_done && (op0 == 4'b0101 || op0 == 4'b0110 || op0 == 4'b0111)) begin
            op0_weight_counter <= op0_weight_counter + num_groups;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            op1_weight_counter <= 0;
        end else if(init) begin
            op1_weight_counter <= 0; 
        end else if (op1_done && (op1 == 4'b0101 || op1 == 4'b0110 || op1 == 4'b0111)) begin
            op1_weight_counter <= op1_weight_counter + num_groups;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            op2_weight_counter <= 0;
        end else if(init) begin
            op2_weight_counter <= 0; 
        end else if (op2_done && (op2 == 4'b0101 || op2 == 4'b0110 || op2 == 4'b0111)) begin
            op2_weight_counter <= op2_weight_counter + num_groups;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            op3_weight_counter <= 0;
        end else if(init) begin
            op3_weight_counter <= 0; 
        end else if (op3_done && (op3 == 4'b0101 || op3 == 4'b0110 || op3 == 4'b0111)) begin
            op3_weight_counter <= op3_weight_counter + num_groups;
        end
    end

    // always @(posedge clk) begin
    //     if(exp_en) $display("exp_en");
    //     if(reciprocal_en) $display("reciprocal_en");
    //     if(conv_en) $display("conv_en");
    // end
endmodule