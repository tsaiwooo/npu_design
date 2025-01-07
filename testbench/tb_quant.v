`timescale 1ns / 1ps

module MultiplyByQuantizedMultiplier_tb;

    // Parameters
    parameter CLK_PERIOD = 10;
    parameter TEST_COUNT = 8;

    // Inputs
    reg clk;
    reg rst;
    reg input_valid;
    reg signed [31:0] x;
    reg [31:0] quantized_multiplier;
    reg signed [31:0] shift;

    // Outputs
    wire output_valid;
    wire signed [7:0] x_mul_by_quantized_multiplier;

    // Test vectors
    reg signed [31:0] test_x [0:TEST_COUNT-1];
    reg [31:0] test_quantized_multiplier [0:TEST_COUNT-1];
    reg signed [31:0] test_shift [0:TEST_COUNT-1];
    reg signed [7:0] golden_results [0:TEST_COUNT-1];
    integer pass_count = 0;
    integer fail_count = 0;
    integer error_count = 0;
    integer i, output_index;
    localparam signed [7:0] NEG_128 = -128;
    localparam signed [7:0] POS_127 =  127;

    // Instantiate the Unit Under Test (UUT)
    MultiplyByQuantizedMultiplier uut (
        .clk(clk),
        .rst(rst),
        .x(x),
        .quantized_multiplier(quantized_multiplier),
        .shift(shift),
        .input_valid(input_valid),
        .output_valid(output_valid),
        .x_mul_by_quantized_multiplier(x_mul_by_quantized_multiplier)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Golden Model for reference calculation
    function signed [7:0] golden_multiply_by_quantized_multiplier(
        input signed [31:0] x,
        input signed [31:0] quantized_multiplier,
        input signed [31:0] shift
    );
        reg signed [63:0] ab_64;
        reg [31:0] remainder, threshold;
        reg signed [31:0] left_shift, right_shift;
        reg signed [31:0] ab_x2_high32;
        reg signed [31:0] nudge;
        reg signed [31:0] mask;
        reg overflow;
        reg signed [31:0] tmp_golden;
        
        begin
            $display("start x = %d, quantized_multiplier = %d", x, quantized_multiplier);
            left_shift = (shift > 0) ? shift : 0;
            right_shift = (shift > 0) ? 0 : -shift;

            ab_64 = x * (64'sd1 << left_shift);
            $display("before_ab_64 = %h", ab_64);
            ab_64 = ab_64 * quantized_multiplier;

            overflow = (x == quantized_multiplier && x == 32'h80000000);
            nudge = (ab_64 >= 0) ? (1 << 30) : (1 - (1 << 30));
            ab_x2_high32 = overflow ? 32'h7fffffff : (ab_64 + nudge) >>> 31;
            $display("x = %d, quantized_multiplier = %d", x, quantized_multiplier);
            $display("left_shift = %d, right_shift = %d", left_shift, right_shift);
            $display("ab_64 = %h", ab_64);
            $display("ab_x2_high32 = %h, mask = %h, remainder = %h", ab_x2_high32, mask, remainder);
            if (ab_64 < -128<<right_shift && right_shift) begin
                golden_multiply_by_quantized_multiplier = -8'd128;
            end else if (ab_64 > 127<<right_shift && right_shift) begin
                golden_multiply_by_quantized_multiplier = 8'd127;
            end else begin
                mask = (1 << right_shift) - 1;
                remainder = ab_x2_high32 & mask;
                threshold = mask >> 1;
                if (ab_x2_high32 < 0)
                    threshold = threshold + 1;

                tmp_golden = ab_x2_high32 >>> right_shift;
                $display("golden_multiply_by_quantized_multiplier = %h", tmp_golden);
                if (remainder > threshold || 
                (remainder == threshold && (ab_x2_high32 & 1) && ab_x2_high32 != 32'h7fffffff))begin
                    golden_multiply_by_quantized_multiplier = (tmp_golden >= $signed(POS_127))? POS_127:
                                                               (tmp_golden < $signed(NEG_128))? NEG_128: tmp_golden + 1;
                end
                else if(tmp_golden > $signed(POS_127)) begin
                    golden_multiply_by_quantized_multiplier = 127;
                end
                else if(tmp_golden < $signed(NEG_128)) begin
                    golden_multiply_by_quantized_multiplier = -128;
                end
                else begin
                    golden_multiply_by_quantized_multiplier = tmp_golden;
                end
            end
        end
    endfunction

    // Initialize test data
    initial begin
        test_x[0] = 32'hffff_e696; test_quantized_multiplier[0] = 32'h0001_0000; test_shift[0] = -12;
        golden_results[0] = golden_multiply_by_quantized_multiplier(test_x[0], test_quantized_multiplier[0], test_shift[0]);

        test_x[1] = 32'd14539; test_quantized_multiplier[1] = 32'h4000000; test_shift[1] = 3;
        golden_results[1] = golden_multiply_by_quantized_multiplier(test_x[1], test_quantized_multiplier[1], test_shift[1]);

        test_x[2] = 32'hffff_e696; test_quantized_multiplier[2] = 32'h40000000; test_shift[2] = 3;
        golden_results[2] = golden_multiply_by_quantized_multiplier(test_x[2], test_quantized_multiplier[2], test_shift[2]);

        test_x[3] = 32'd14539; test_quantized_multiplier[3] = 32'h40000000; test_shift[3] = 3;
        golden_results[3] = golden_multiply_by_quantized_multiplier(test_x[3], test_quantized_multiplier[3], test_shift[3]);

        test_x[4] = -32'd26; test_quantized_multiplier[4] = 32'h40000000; test_shift[4] = 3;
        golden_results[4] = golden_multiply_by_quantized_multiplier(test_x[4], test_quantized_multiplier[4], test_shift[4]);

        test_x[5] = 32'd1024; test_quantized_multiplier[5] = 32'd512; test_shift[5] = 1;
        golden_results[5] = golden_multiply_by_quantized_multiplier(test_x[5], test_quantized_multiplier[5], test_shift[5]);

        test_x[6] = 32'd9999; test_quantized_multiplier[6] = 32'd3333; test_shift[6] = 8;
        golden_results[6] = golden_multiply_by_quantized_multiplier(test_x[6], test_quantized_multiplier[6], test_shift[6]);

        test_x[7] = -32'd256; test_quantized_multiplier[7] = 32'd128; test_shift[7] = -2;
        golden_results[7] = golden_multiply_by_quantized_multiplier(test_x[7], test_quantized_multiplier[7], test_shift[7]);
    end

    // Apply reset and test patterns
    initial begin
        rst = 0;
        input_valid = 0;
        output_index = 0;

        // Apply reset
        #(CLK_PERIOD * 2);
        rst = 1;
        #(CLK_PERIOD);

        // Send each test vector
        for (i = 0; i < TEST_COUNT; i = i + 1) begin
            @(negedge clk);
            input_valid = 1;
            x = test_x[i];
            quantized_multiplier = test_quantized_multiplier[i];
            shift = test_shift[i];
            $display("Sending test vector %0d: x = %d, quantized_multiplier = %d, shift = %d", i, test_x[i], test_quantized_multiplier[i], test_shift[i]);
        end
        @(negedge clk);
        input_valid = 0;
    end

    // Monitor outputs and validate
    always @(posedge clk) begin
        if (output_valid) begin
            $display("Received output %0d: %d", output_index, x_mul_by_quantized_multiplier);
            if (x_mul_by_quantized_multiplier == golden_results[output_index]) begin
                $display("Test %0d PASSED, GOLDEN = %0d", output_index, golden_results[output_index]);
                pass_count = pass_count + 1;
            end else begin
                $display("Test %0d FAILED, GOLDEN = %0d", output_index, golden_results[output_index]);
                fail_count = fail_count + 1;
            end
            output_index = output_index + 1;

            // Finish if all outputs are verified
            if (output_index == TEST_COUNT) begin
                $display("------------------------------------------------");
                $display("Total PASS Count: %0d", pass_count);
                $display("Total FAIL Count: %0d", fail_count);
                $finish;
            end
        end
    end
endmodule
