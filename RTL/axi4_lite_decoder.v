`timescale 1ns / 1ps
`include "params.vh"

module axi4_lite_decoder (
    input  wire         axi_aclk,        
    input  wire         axi_aresetn,     

    // Write address channel:
    input  wire [31:0]  S_AXI_AWADDR,    
    input  wire         S_AXI_AWVALID,   
    output reg          S_AXI_AWREADY,   

    // Write data channel:
    input  wire [31:0]  S_AXI_WDATA,     
    input  wire [3:0]   S_AXI_WSTRB,     
    input  wire         S_AXI_WVALID,    
    output reg          S_AXI_WREADY,    

    // Write response channel:
    output reg [1:0]    S_AXI_BRESP,     
    output reg          S_AXI_BVALID,    
    input  wire         S_AXI_BREADY,    

    // Read address channel:
    input  wire [31:0]  S_AXI_ARADDR,    
    input  wire         S_AXI_ARVALID,   
    output reg          S_AXI_ARREADY,   

    // Read data channel:
    output reg [31:0]   S_AXI_RDATA,     
    output reg [1:0]    S_AXI_RRESP,     
    output reg          S_AXI_RVALID,    
    input  wire         S_AXI_RREADY,    

    // Configuration registers:
    output reg [31:0]   cfg_quantized_multiplier,
    output reg [31:0]   cfg_shift,
    output reg [31:0]   cfg_input_zero_point,
    output reg [31:0]   cfg_input_range_radius,
    output reg [31:0]   cfg_input_left_shift,
    output reg [31:0]   cfg_input_multiplier
);

    // Internal signals
    reg [31:0] write_addr;
    reg        write_addr_valid;
    reg        write_data_valid;

    always @(posedge axi_aclk) begin
        if (!axi_aresetn) begin
            // Reset handshake signals
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= 2'b00;
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RRESP   <= 2'b00;

            // Reset internal registers
            cfg_quantized_multiplier <= 32'd0;
            cfg_shift                <= 32'd0;
            cfg_input_zero_point     <= 32'd0;
            cfg_input_range_radius   <= 32'd0;
            cfg_input_left_shift     <= 32'd0;
            cfg_input_multiplier     <= 32'd0;

            // Reset internal control signals
            write_addr       <= 32'd0;
            write_addr_valid <= 1'b0;
            write_data_valid <= 1'b0;

        end else begin
            // === Write Address Channel ===
            if (S_AXI_AWVALID && !S_AXI_AWREADY) begin
                S_AXI_AWREADY <= 1'b1;
                write_addr    <= S_AXI_AWADDR;
                write_addr_valid <= 1'b1;
            end else begin
                S_AXI_AWREADY <= 1'b0;
            end

            // === Write Data Channel ===
            if (S_AXI_WVALID && !S_AXI_WREADY) begin
                S_AXI_WREADY <= 1'b1;
                write_data_valid <= 1'b1;
            end else begin
                S_AXI_WREADY <= 1'b0;
            end

            // === Perform Register Write ===
            if (write_addr_valid && write_data_valid) begin
                case (write_addr[7:0])
                    8'h00: cfg_quantized_multiplier <= S_AXI_WDATA;
                    8'h04: cfg_shift                <= S_AXI_WDATA;
                    8'h08: cfg_input_zero_point     <= S_AXI_WDATA;
                    8'h0C: cfg_input_range_radius   <= S_AXI_WDATA;
                    8'h10: cfg_input_left_shift     <= S_AXI_WDATA;
                    8'h14: cfg_input_multiplier     <= S_AXI_WDATA;
                    default: ; // Ignore invalid addresses
                endcase
                write_addr_valid <= 1'b0;
                write_data_valid <= 1'b0;
                S_AXI_BVALID     <= 1'b1;
                S_AXI_BRESP      <= 2'b00; // OKAY response
            end

            // === Write Response Channel ===
            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end

            // === Read Address Channel ===
            if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
                S_AXI_ARREADY <= 1'b1;
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end

            // === Read Data Channel ===
            if (S_AXI_ARREADY) begin
                S_AXI_RVALID <= 1'b1;
                case (S_AXI_ARADDR[7:0])
                    8'h00: S_AXI_RDATA <= cfg_quantized_multiplier;
                    8'h04: S_AXI_RDATA <= cfg_shift;
                    8'h08: S_AXI_RDATA <= cfg_input_zero_point;
                    8'h0C: S_AXI_RDATA <= cfg_input_range_radius;
                    8'h10: S_AXI_RDATA <= cfg_input_left_shift;
                    8'h14: S_AXI_RDATA <= cfg_input_multiplier;
                    default: S_AXI_RDATA <= 32'd0;
                endcase
                S_AXI_RRESP <= 2'b00; // OKAY response
            end

            // Clear RVALID when read is accepted
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end
endmodule
