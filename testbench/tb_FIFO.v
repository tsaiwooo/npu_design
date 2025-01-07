`timescale 1ns/1ps

module FIFO_tb;

    // -----------------------------------------------------
    // Testbench Parameters (must match DUT)
    // -----------------------------------------------------
    parameter DATA_WIDTH = 32;
    parameter DEPTH      = 8;
    parameter ADDR_WIDTH = 3;

    // -----------------------------------------------------
    // DUT I/O signals
    // -----------------------------------------------------
    reg                   clk;
    reg                   rst;       // active-low reset
    reg                   wr;        // write enable
    reg                   rd;        // read enable
    reg  [DATA_WIDTH-1:0] data_in;

    wire [DATA_WIDTH-1:0] data_out;
    wire                   fill;      // same as "full"
    wire                   empty;

    // -----------------------------------------------------
    // Instantiate the FIFO (Device Under Test)
    // -----------------------------------------------------
    FIFO #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .wr       (wr),
        .rd       (rd),
        .data_in  (data_in),
        .data_out (data_out),
        .full     (fill),
        .empty    (empty)
    );
    initial begin
        // FSDB file name
        $fsdbDumpfile("verdi.fsdb");
        // Dump all variables in the design hierarchy (from tb_mac)
        $fsdbDumpvars(0, FIFO_tb, "+all");
    end

    // -----------------------------------------------------
    // Clock Generation: 10ns period => 100MHz
    // -----------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // toggle every 5 ns
    end

    // -----------------------------------------------------
    // Initial reset + Test Sequence
    // -----------------------------------------------------
    reg [DATA_WIDTH-1:0] test1_exp [0:3];
    reg [DATA_WIDTH-1:0] got_data [0:3];
    initial begin
        // Initialize signals
        integer i;
        integer mismatch_count;
        rst     = 1'b1;   // active-low reset
        wr      = 1'b0;
        rd      = 1'b0;
        data_in = {DATA_WIDTH{1'b0}};

        // Apply reset
        @(negedge clk);
        rst = 1'b0;
        // #10;
        @(negedge clk);
        rst = 1'b1;  // release reset

        // Wait a few cycles
        // #20;
        @(posedge clk);

        // -------------------------------------------------
        // Test #1: Write 4 data words
        // -------------------------------------------------
        $display("\n=== Test #1: Write 4 words ===");
        test1_exp[0] = 32'h0000_0001;
        test1_exp[1] = 32'h0000_0002;
        test1_exp[2] = 32'h0000_0003;
        test1_exp[3] = 32'h0000_0004;

        for (i=0; i<4; i=i+1) begin
            write_data(test1_exp[i]);
        end

        $display("Test #1 complete. (No direct pass/fail check here)");

        #20;

        // -------------------------------------------------
        // Test #2: Read 4 words, check correctness
        // -------------------------------------------------
        $display("\n=== Test #2: Read 4 words and compare ===");
        for (i=0; i<4; i=i+1) begin
            read_data_task(got_data[i]);
        end

        mismatch_count = 0;
        for (i=0; i<4; i=i+1) begin
            if (got_data[i] !== test1_exp[i]) begin
                mismatch_count = mismatch_count + 1;
                $display(" MISMATCH: got=%h, exp=%h (index=%0d)", 
                         got_data[i], test1_exp[i], i);
            end
        end

        if (mismatch_count == 0) begin
            $display("Test #2 success!");
        end else begin
            $display("Test #2 fail! %0d mismatch(es).", mismatch_count);
        end

        #20;

        // -------------------------------------------------
        // Test #3: Fill the FIFO completely
        //          and check 'fill'
        // -------------------------------------------------
        $display("\n=== Test #3: Fill the FIFO (DEPTH=%0d) and check fill ===", DEPTH);
        for (i=0; i<DEPTH; i=i+1) begin
            write_data(32'hAAAA_0000 + i);
        end

        // Wait a bit to update fill
        #10;
        if (fill) begin
            $display("Test #3 success! FIFO is FULL (fill=1) as expected.");
        end else begin
            $display("Test #3 fail! FIFO not full, but expected it to be.");
        end

        #20;

        // -------------------------------------------------
        // Test #4: Read all data out, check 'empty'
        // -------------------------------------------------
        $display("\n=== Test #4: Read all data, check empty ===");
        for (i=0; i<DEPTH; i=i+1) begin
            reg [DATA_WIDTH-1:0] dummy;
            read_data_task(dummy); // 這裡不特別比對
        end

        #10;
        if (empty) begin
            $display("Test #4 success! FIFO is EMPTY (empty=1) as expected.");
        end else begin
            $display("Test #4 fail! FIFO not empty, but expected it to be.");
        end

        #20;
        $display("\n=== All tests completed. Simulation ends. ===");
        $finish;
    end

    // -----------------------------------------------------
    // Task: Write data to the FIFO (one cycle)
    // -----------------------------------------------------
    task write_data(input [DATA_WIDTH-1:0] d);
    begin
        @(posedge clk);
        if (!fill) begin
            wr      <= 1'b1;
            data_in <= d;
        end else begin
            $display($time, " [write_data] FAIL: FIFO FULL! Can't write 0x%h", d);
        end

        @(posedge clk);
        wr      <= 1'b0;
        data_in <= {DATA_WIDTH{1'b0}};
    end
    endtask

    // -----------------------------------------------------
    // Task: Read data from the FIFO (zero-cycle latency)
    //       *Now a task*, because function can't have @
    // -----------------------------------------------------
    task read_data_task(output [DATA_WIDTH-1:0] out_data);
        reg [DATA_WIDTH-1:0] tmp_data;
    begin
        @(posedge clk);
        if (!empty) begin
            rd = 1'b1;
        end else begin
            $display($time, " [read_data_task] FAIL: FIFO EMPTY! Can't read.");
        end

        // Zero-cycle latency => same cycle data_out is valid
        tmp_data = data_out;

        @(posedge clk);
        rd = 1'b0;

        out_data = tmp_data;  // pass data back to caller
    end
    endtask

endmodule
