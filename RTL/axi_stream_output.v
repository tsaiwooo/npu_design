`timescale 1ns / 1ps

module axi_stream_output #
(
    parameter ADDR_WIDTH = 13,
    parameter DATA_WIDTH = 8,
    parameter NUM_CHANNELS_WIDTH = $clog2(64+1)
)
(
    input  wire                   m_axis_aclk,
    input  wire                   m_axis_aresetn,
    output reg signed [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast,
    output reg [NUM_CHANNELS_WIDTH-1:0] m_axis_tuser,

    // sram control interface
    output reg                    sram_out_en,
    output reg [MAX_ADDR_WIDTH-1:0]   sram_out_addr,
    input  wire signed [SRAM_WIDTH_O-1:0] sram_out_data_out,

    // control_signals
    input  wire                   start_output,
    input  wire [MAX_ADDR_WIDTH-1:0]  out_size
);

    reg [MAX_ADDR_WIDTH-1:0] read_counter;
    reg                  output_done;
    reg                  data_valid_reg;  
    reg [MAX_ADDR_WIDTH-1:0] prefetch_addr; 

    wire data_ready = data_valid_reg && (m_axis_tready || !m_axis_tvalid);
    wire reset_condition = !m_axis_aresetn;
    wire start_condition = start_output && !output_done;

    // Control sram_out_en
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            sram_out_en <= 1'b0;
        end else if (start_condition) begin
            sram_out_en <= data_ready || !data_valid_reg;
        end else begin
            sram_out_en <= 1'b0;
        end
    end

    // Control sram_out_addr
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            sram_out_addr <= {MAX_ADDR_WIDTH{1'b0}};
        end else if (start_condition && (data_ready || !data_valid_reg)) begin
            sram_out_addr <= prefetch_addr;
            $display("sram_out_addr: %d, data = %h", sram_out_addr, sram_out_data_out);
        end else begin
            sram_out_addr <= {MAX_ADDR_WIDTH{1'b0}};
        end
    end

    // Control m_axis_tdata
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            m_axis_tdata <= {SRAM_WIDTH_O{1'b0}};
        end else if (start_condition && data_ready) begin
            m_axis_tdata <= $signed(sram_out_data_out[DATA_WIDTH-1:0]);
        end else begin
            m_axis_tdata <= {SRAM_WIDTH_O{1'b0}};
        end
    end

    // Control m_axis_tvalid
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            m_axis_tvalid <= 1'b0;
        end else if (start_condition) begin
            if (read_counter >= (out_size - 1)) begin
                m_axis_tvalid <= 1'b0;
            end else if (data_ready) begin
                m_axis_tvalid <= 1'b1;
            end else begin
                m_axis_tvalid <= 1'b0;
            end
        end else begin
            m_axis_tvalid <= 1'b0;
        end
    end

    // Control m_axis_tlast
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            m_axis_tlast <= 1'b0;
        end else if (start_condition && data_ready) begin
            m_axis_tlast <= (read_counter == (out_size - 2));
        end else begin
            m_axis_tlast <= 1'b0;
        end
    end

    // Control m_axis_tuser
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            m_axis_tuser <= {NUM_CHANNELS_WIDTH{1'b0}};
        end else if (start_condition && data_ready) begin
            m_axis_tuser <= 0;
        end else begin
            m_axis_tuser <= {NUM_CHANNELS_WIDTH{1'b0}};
        end
    end

    // Control read_counter
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            read_counter <= {MAX_ADDR_WIDTH{1'b0}};
        end else if (start_condition && data_ready) begin
            if (read_counter < (out_size - 1)) begin
                read_counter <= read_counter + 1;
            end else begin
                read_counter <= {MAX_ADDR_WIDTH{1'b0}};
            end
        end else begin
            read_counter <= {MAX_ADDR_WIDTH{1'b0}};
        end
    end

    // Control output_done
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            output_done <= 1'b0;
        end else if (start_condition && data_ready && (read_counter >= (out_size - 1))) begin
            output_done <= 1'b1;
        end else begin
            output_done <= 1'b0;
        end
    end

    // Control data_valid_reg
    always @(posedge m_axis_aclk) begin
        if (reset_condition || !start_output) begin
            data_valid_reg <= 1'b0;
        end else if (start_condition) begin
            if (data_ready) begin
                data_valid_reg <= 1'b1;
            end else if (!data_valid_reg && sram_out_en) begin
                data_valid_reg <= 1'b1;
            end else begin
                data_valid_reg <= 1'b0;
            end
        end else begin
            data_valid_reg <= 1'b0;
        end
    end

    // Control prefetch_addr
    always @(posedge m_axis_aclk) begin
        if (reset_condition) begin
            prefetch_addr <= {MAX_ADDR_WIDTH{1'b0}};
        end else if (start_condition && (data_ready || !data_valid_reg)) begin
            prefetch_addr <= prefetch_addr + 1;
        end else begin
            prefetch_addr <= {MAX_ADDR_WIDTH{1'b0}};
        end
    end

endmodule
