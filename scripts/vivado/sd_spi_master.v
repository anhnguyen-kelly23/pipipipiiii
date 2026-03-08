`timescale 1ns / 1ps
//============================================================================
// SD SPI Master - FIXED VERSION
// CS được điều khiển riêng, không tự động toggle
//============================================================================

module sd_spi_master (
    input clk,
    input resetn,

    // Data interface
    input [7:0] tx_data,
    input tx_valid,
    output reg tx_ready,

    output reg [7:0] rx_data,
    output reg rx_valid,

    // CS control - điều khiển từ bên ngoài
    input cs_enable,      // 1 = CS low (active), 0 = CS high

    // Clock divider
    input [15:0] clk_div,

    // SPI signals
    output reg sd_clk,
    output reg sd_mosi,
    input  sd_miso,
    output reg sd_cs
);

// Clock divider
reg [15:0] div_cnt;
reg spi_tick;

always @(posedge clk) begin
    if (!resetn) begin
        div_cnt <= 0;
        spi_tick <= 0;
    end else begin
        if (div_cnt >= clk_div) begin
            div_cnt <= 0;
            spi_tick <= 1;
        end else begin
            div_cnt <= div_cnt + 1;
            spi_tick <= 0;
        end
    end
end

// SPI state machine
reg [2:0] bit_cnt;
reg [7:0] shift_tx;
reg [7:0] shift_rx;
reg busy;
reg clk_phase;  // 0 = rising edge, 1 = falling edge

always @(posedge clk) begin
    if (!resetn) begin
        sd_clk <= 0;
        sd_mosi <= 1;
        sd_cs <= 1;
        busy <= 0;
        tx_ready <= 1;
        rx_valid <= 0;
        bit_cnt <= 0;
        shift_tx <= 8'hFF;
        shift_rx <= 8'hFF;
        clk_phase <= 0;
    end else begin
        // CS control - từ bên ngoài
        sd_cs <= ~cs_enable;
        
        rx_valid <= 0;

        if (!busy) begin
            // Idle - ready to accept new byte
            if (tx_valid && tx_ready) begin
                busy <= 1;
                tx_ready <= 0;
                bit_cnt <= 7;
                shift_tx <= tx_data;
                shift_rx <= 8'hFF;
                clk_phase <= 0;
                sd_mosi <= tx_data[7];  // Set first bit immediately
            end
        end else if (spi_tick) begin
            // Transferring
            if (clk_phase == 0) begin
                // Rising edge - sample MISO
                sd_clk <= 1;
                shift_rx[bit_cnt] <= sd_miso;
                clk_phase <= 1;
            end else begin
                // Falling edge - shift out next bit
                sd_clk <= 0;
                clk_phase <= 0;
                
                if (bit_cnt == 0) begin
                    // Done with this byte
                    busy <= 0;
                    tx_ready <= 1;
                    rx_data <= shift_rx;
                    rx_data[0] <= sd_miso;  // Last bit
                    rx_valid <= 1;
                    sd_mosi <= 1;  // MOSI high when idle
                end else begin
                    bit_cnt <= bit_cnt - 1;
                    sd_mosi <= shift_tx[bit_cnt - 1];
                end
            end
        end
    end
end

endmodule
