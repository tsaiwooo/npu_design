`timescale 1ns / 1ps
// Modify: 
// 1. Last cycle錯了 應該提早一個cycle
// 2. weight那邊有問題, 只收到8個而已
// 3. 
module tb_npu();

// Parameters
parameter PERIOD              = 10;
parameter MAX_MACS            = 64;
parameter ADDR_WIDTH          = 18;
parameter C_AXIS_TDATA_WIDTH  = 8;
parameter C_AXIS_MDATA_WIDTH  = 8;
parameter MAX_CHANNELS        = 64;
parameter NUM_CHANNELS_WIDTH  = $clog2(MAX_CHANNELS+1);

// Variables
integer img_file, weight_file, scan_result;
// integer img_row, img_col, ker_row, ker_col;
reg [ADDR_WIDTH-1:0] img_row, img_col, ker_row, ker_col;
integer i, j, m, n;

// Buffers for storing image and weight data
reg signed [C_AXIS_TDATA_WIDTH-1:0] img_buffer [0:2**ADDR_WIDTH-1];
reg signed [C_AXIS_TDATA_WIDTH-1:0] weight_buffer [0:2**ADDR_WIDTH-1];
reg signed [2*C_AXIS_MDATA_WIDTH-1:0] expected_output [0:2**ADDR_WIDTH-1];

// Inputs
reg   s00_axis_aclk    = 0;
reg   s00_axis_aresetn = 1;
reg   [C_AXIS_TDATA_WIDTH-1:0] s00_axis_tdata = 0;
reg   s00_axis_tvalid  = 0;
reg   s00_axis_tlast   = 0;
reg   [2*ADDR_WIDTH + NUM_CHANNELS_WIDTH-1:0] s00_axis_tuser = 0;
reg   m00_axis_aclk    = 0;
reg   m00_axis_aresetn = 1;
reg   m00_axis_tready  = 0;

// Outputs
wire  s00_axis_tready;
wire  signed [2*C_AXIS_MDATA_WIDTH-1:0] m00_axis_tdata;
wire  m00_axis_tvalid;
wire  m00_axis_tlast;
wire  [NUM_CHANNELS_WIDTH-1:0] m00_axis_tuser;
wire [(C_AXIS_TDATA_WIDTH/8)-1 : 0] dump;

// Clock generation
initial begin
    forever #(PERIOD/2) s00_axis_aclk = ~s00_axis_aclk;
    // forever #(PERIOD/2) m00_axis_aclk = ~m00_axis_aclk;
end

initial begin
    // forever #(PERIOD/2) s00_axis_aclk = ~s00_axis_aclk;
    forever #(PERIOD/2) m00_axis_aclk = ~m00_axis_aclk;
end

initial begin
    // FSDB file name
    $fsdbDumpfile("verdi.fsdb");
    // Dump all variables in the design hierarchy (from tb_mac)
    $fsdbDumpvars(0, tb_npu, "+all");
end

// Reset logic
initial begin
    s00_axis_aresetn = 0;
    m00_axis_aresetn = 0;
    #(PERIOD * 2);
    s00_axis_aresetn = 1;
    m00_axis_aresetn = 1;
end

// Instantiate NPU
npu #(
    .MAX_MACS(MAX_MACS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .C_AXIS_TDATA_WIDTH(C_AXIS_TDATA_WIDTH),
    .C_AXIS_MDATA_WIDTH(C_AXIS_MDATA_WIDTH),
    .MAX_CHANNELS(MAX_CHANNELS),
    .NUM_CHANNELS_WIDTH(NUM_CHANNELS_WIDTH)
) u_npu (
    .s00_axis_aclk(s00_axis_aclk),
    .s00_axis_aresetn(s00_axis_aresetn),
    .s00_axis_tdata(s00_axis_tdata),
    .s00_axis_tvalid(s00_axis_tvalid),
    .s00_axis_tlast(s00_axis_tlast),
    .s00_axis_tuser(s00_axis_tuser),
    .s00_axis_tstrb(dump),
    .m00_axis_aclk(m00_axis_aclk),
    .m00_axis_aresetn(m00_axis_aresetn),
    .m00_axis_tready(m00_axis_tready),
    .s00_axis_tready(s00_axis_tready),
    .m00_axis_tdata(m00_axis_tdata),
    .m00_axis_tvalid(m00_axis_tvalid),
    .m00_axis_tlast(m00_axis_tlast),
    .m00_axis_tuser(m00_axis_tuser),
    .m00_axis_tstrb()
);

// Read image and weight data into buffers
initial begin
    img_file = $fopen("image_data.txt", "r");
    weight_file = $fopen("kerenl_data.txt", "r");

    // Read image dimensions
    scan_result = $fscanf(img_file, "%d %d\n", img_row, img_col);
    for (i = 0; i < img_row * img_col; i = i + 1) begin
        scan_result = $fscanf(img_file, "%d\n", img_buffer[i]);
    end

    // Read weight dimensions
    scan_result = $fscanf(weight_file, "%d %d\n", ker_row, ker_col);
    for (i = 0; i < ker_row * ker_col; i = i + 1) begin
        scan_result = $fscanf(weight_file, "%d\n", weight_buffer[i]);
    end

    $fclose(img_file);
    $fclose(weight_file);
end

// Send image data from buffer
integer tmp;
task send_image;
begin
    $display("img_row = %d, img_col = %d, last = %d", img_row, img_col, img_row * img_col - 1);
    @(posedge s00_axis_aclk);
    for (i = 0; i < img_row * img_col; i = i + 1) begin
        s00_axis_tdata = img_buffer[i];
        s00_axis_tvalid = 1;
        // $display("i = %d, valid = %d", i, s00_axis_tvalid);
        s00_axis_tlast = (i == img_row * img_col - 1);
        tmp = 1;
        s00_axis_tuser = {img_row, img_col, tmp[NUM_CHANNELS_WIDTH-1:0]};  // Send metadata in tuser
        wait(s00_axis_tready);
        @(posedge s00_axis_aclk);
    end
    s00_axis_tvalid = 0;
    s00_axis_tlast = 0;
end
endtask

// Send weight data from buffer
task send_weight;
begin
    $display("ker_row = %d, ker_col = %d, last = %d", ker_row, ker_col, ker_row * ker_col - 1);
    @(posedge s00_axis_aclk);
    for (i = 0; i < ker_row * ker_col; i = i + 1) begin
        s00_axis_tdata = weight_buffer[i];
        s00_axis_tvalid = 1;
        s00_axis_tlast = (i == ker_row * ker_col - 1);
        tmp = 1;
        s00_axis_tuser = {ker_row, ker_col, tmp[NUM_CHANNELS_WIDTH-1:0]};  // Send metadata in tuser
        wait(s00_axis_tready);
        @(posedge s00_axis_aclk);
    end
    s00_axis_tvalid = 0;
    s00_axis_tlast = 0;
end
endtask

// Perform Convolution and store expected output
task compute_convolution;
begin
    reg signed [2*C_AXIS_MDATA_WIDTH-1: 0] sum;
    for (i = 0; i <= img_row - ker_row; i = i + 1) begin
        for (j = 0; j <= img_col - ker_col; j = j + 1) begin
            sum = 0;
            for (m = 0; m < ker_row; m = m + 1) begin
                for (n = 0; n < ker_col; n = n + 1) begin
                    sum = sum + img_buffer[(i + m) * img_col + (j + n)] *
                          weight_buffer[m * ker_col + n];
                end
            end
            expected_output[i * (img_col - ker_col + 1) + j] = sum;
            // if(i==0 && j==0)begin
            //     $display("sum = %b", sum);
            // end
        end
    end
end
endtask

// Check output and compare with expected output
task check_output;
begin
    integer total_elements;

    integer idx = 0;
    total_elements = (img_row - ker_row + 1) * (img_col - ker_col + 1);
    @(posedge m00_axis_aclk);
    m00_axis_tready = 1;
    // while (!m00_axis_tvalid) begin
    //     $display("Waiting for valid output");
    //     @(posedge m00_axis_aclk);
    // end
    wait(m00_axis_tvalid);

    while (m00_axis_tvalid) begin
        @(posedge m00_axis_aclk);
        if(^m00_axis_tdata === 1'bx)begin
            $display("Invalid data at index %d, Expected %d", idx, expected_output[idx]);
            $finish;
        end else if (m00_axis_tdata !== expected_output[idx]) begin
            $display("Mismatch at index %d: Expected %d, Got %d", idx, expected_output[idx], m00_axis_tdata);
            $finish;
        end else begin
            $display("Match at index %d: %d", idx, m00_axis_tdata);
        end
        idx = idx + 1;
    end
end
endtask


// Check data in SRAM[0] and compare with img_buffer
task check_sram_data;
begin
    integer idx = 0;
    integer total_elements;

    total_elements = img_row * img_col;

    @(posedge m00_axis_aclk);
    m00_axis_tready = 1;

    while (!m00_axis_tvalid) begin
        $display("Waiting for valid data from SRAM[0]");
        @(posedge m00_axis_aclk);
    end

    // 比對 SRAM[0] 中的所有資料
    while (idx < total_elements) begin
        wait(m00_axis_tvalid && m00_axis_tready); // 確保 AXI4-Stream 資料有效
        @(posedge m00_axis_aclk);
        m00_axis_tready = 1;

        if (m00_axis_tdata !== img_buffer[idx]) begin
            $display("Mismatch at index %d: Expected %d, Got %d, total_elements = %d", 
                     idx, img_buffer[idx], m00_axis_tdata,total_elements);
            $finish; 
        end else begin
            $display("Match at index %d: %d", idx, m00_axis_tdata);
        end

        idx = idx + 1; 
    end

    $display("All SRAM[0] data matches the input image data!");
end
endtask


initial
begin
    // $display("%s", "exit1");
    # (PERIOD * 10);  // Wait for reset to complete
    compute_convolution();
    // $display("%s", "exit2");
    send_image();
    // $display("%s", "exit3");
    send_weight();
    // $display("%s", "exit4");
    # (PERIOD * 3300000);  // Wait for NPU processing
    // wait(m00_axis_tvalid);
    check_output();      // 檢查 SRAM[0] 中的資料
    // check_sram_data();
    $display("%s", "                                                                      :+**************-.            ");
    $display("%s", "                                                                     :+****************.            ");
    $display("%s", "                                                                     :+*****++++*******.            ");
    $display("%s", "                                                                     :+*****:.-..=*****.            ");
    $display("%s", "                                                                     :+*****:.-:.=*****.            ");
    $display("%s", "                                                                     :+*****::++*******.            ");
    $display("%s", "                                                                     :+*****--*********.            ");
    $display("%s", "                                     ..                   .=*+.      :+****************.            ");
    $display("%s", "                         .:--.     :*##*:                .*###++=.   :+****************.            ");
    $display("%s", "          .+##*-.       .+####+.  :#####-     .=###-. :*#########+.  :+***+=-::::-++***.            ");
    $display("%s", "         .*#####:        +#####+..*#####-     .=####=.*#########++*###*+:.                          ");
    $display("%s", "         .######:        :######:.*####*:     .:####+..::-###############*.                         ");
    $display("%s", "         .+#####-        .+#####-.=####*:      .+###*.  .-#####*+-:::=####+.                        ");
    $display("%s", "          -#####+.       .+#####: :#####-       =###*...+#####-      .=###*.                        ");
    $display("%s", "          .*#####:        :*##+:. .+#####-.     .+*=..:*######-  ... .+###+.                        ");
    $display("%s", "           :######:.       ...     .*#####+.          -#######::*########*:.                        ");
    $display("%s", "           .:######+.               .*#####-          ...-###*:###*-####*.                          ");
    $display("%s", "            .-######*.               .:*#*=.            .-###+.:*#########:.                        ");
    $display("%s", "              :*####*.                   .......         .++-.  .... .=###=.                        ");
    $display("%s", "               .:==-..              .:+#%#***##%#=.                  ..:..                         ");
    $display("%s", "                                .-*#+-............:+#*-.               ..:..                        ");
    $display("%s", "           .....    ..-*##*=..:#%=....................-%#::*%%%*.. ...:..                          ");
    $display("%s", "            ..::.   =#-....:#%=.........................:##.....:**.....                            ");
    $display("%s", "               .:. :#.....:%+.....................................#- ....:..                        ");
    $display("%s", "           ......  =*.............................................*= .......                        ");
    $display("%s", "           ....:.. .#=...........................................-#:                                ");
    $display("%s", "                    .*%=#-....................................:%@*.  .:....                         ");
    $display("%s", "                 ..   :#-.........................--............*=    ...::.                        ");
    $display("%s", "            ...::... :%-........-%@%:...-+***+-..-%@%:..........-#:                                 ");
    $display("%s", "            ....    .#+..........:...=%#::=+-.-#%:...............**.                                ");
    $display("%s", "                    -#.............=%=.-%@@%=....*+..............:%##:                             ");
    $display("%s", "              .=%##:*=...........-%+.....=#.....-=*#.............=#:.++                             ");
    $display("%s", "              =*..=@#:..........-%:=@#=::-#::=*%%@*=#............=#:.#%%+.                         ");
    $display("%s", "             .*+..=@*...........*=:%%+---==---=##-..**............%-#+...*+.                        ");
    $display("%s", "           .+%#@#*-%*...........#=....-*#%%%#++:.....-@:..........:%:-%-..*+.                        ");
    $display("%s", "           -%:...-#:#-..........*+......==-:-*#.....+#...........:%:.##..++.                        ");
    $display("%s", "           -%:...=%:++..........:#*:.....:-=:.....:*#.............#=.+#+=*+.                        ");
    $display("%s", "           .#=...:#-++............:=#%@@%%%%%#%*=...............#=.=+*%=.                         ");
    $display("%s", "            .**=+#+.*%-.........................................=%-.#+..                            ");
    $display("%s", "              ...#=...+%#+=..................................-%#-.-#-                               ");
    $display("%s", "                 .=%+............................................**.                                ");
    $display("%s", "                    .=*#*.....................................:#*:                                  ");
    $display("%s", "                      .=%.....................................:%:                                   ");
    $display("%s", "                      .:-......................................-.                                   ");
    $finish;
end

endmodule