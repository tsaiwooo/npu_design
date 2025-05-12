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
    output reg signed [2*DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast,
    output reg [NUM_CHANNELS_WIDTH-1:0] m_axis_tuser,

    // sram control interface
    output reg                    sram_out_en,
    output reg [ADDR_WIDTH-1:0]   sram_out_addr,
    input  wire signed [2*DATA_WIDTH-1:0] sram_out_data_out,

    // control_signals
    input  wire                   start_output,
    input  wire [ADDR_WIDTH-1:0]  out_row,
    input  wire [ADDR_WIDTH-1:0]  out_col
);

    reg [ADDR_WIDTH-1:0] read_counter;
    reg                  output_done;
    reg                    data_valid_reg;  
    reg [ADDR_WIDTH-1:0] prefetch_addr; 

    always @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            sram_out_en       <= 1'b0;
            sram_out_addr     <= {ADDR_WIDTH{1'b0}};
            m_axis_tdata      <= {2*DATA_WIDTH{1'b0}};
            m_axis_tvalid     <= 1'b0;
            m_axis_tlast      <= 1'b0;
            m_axis_tuser      <= {NUM_CHANNELS_WIDTH{1'b0}};
            read_counter      <= {ADDR_WIDTH{1'b0}};
            output_done       <= 1'b0;
            data_valid_reg    <= 1'b0;
            prefetch_addr     <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (start_output && !output_done) begin
                if (data_valid_reg && (m_axis_tready || !m_axis_tvalid)) begin
                    m_axis_tdata  <= sram_out_data_out;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tuser  <= 0;

                    if (read_counter == (out_row * out_col - 2)) begin
                        m_axis_tlast <= 1'b1;
                    end else begin
                        m_axis_tlast <= 1'b0;
                    end

                    if (read_counter < (out_row * out_col - 1)) begin
                        read_counter <= read_counter + 1;
                    end else begin
                        read_counter <= {ADDR_WIDTH{1'b0}};
                        output_done  <= 1'b1;
                        m_axis_tvalid <= 1'b0;
                    end

                    data_valid_reg    <= 1'b1;

                    sram_out_en   <= 1'b1;
                    sram_out_addr <= prefetch_addr;

                    prefetch_addr <= prefetch_addr + 1;

                end else if (!data_valid_reg) begin
                    sram_out_en       <= 1'b1;
                    sram_out_addr     <= prefetch_addr;
                    prefetch_addr     <= prefetch_addr + 1;
                    data_valid_reg    <= 1'b0;

                    if (sram_out_en) begin
                        data_valid_reg    <= 1'b1;
                    end
                end else begin
                    m_axis_tvalid <= 1'b0;
                end

            end else begin
                m_axis_tvalid     <= 1'b0;
                m_axis_tlast      <= 1'b0;
                sram_out_en       <= 1'b0;
                data_valid_reg    <= 1'b0;
                output_done       <= 1'b0;
                read_counter      <= {ADDR_WIDTH{1'b0}};
                prefetch_addr     <= {ADDR_WIDTH{1'b0}};
            end
        end
    end

endmodule
