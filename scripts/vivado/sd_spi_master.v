`timescale 1ns / 1ps

module sd_spi_master (
    input clk,
    input resetn,

    input [7:0] tx_data,
    input tx_valid,
    output reg tx_ready,

    output reg [7:0] rx_data,
    output reg rx_valid,

    input [15:0] clk_div,

    output reg sd_clk,
    output reg sd_mosi,
    input  sd_miso,
    output reg sd_cs
);

reg [15:0] div_cnt;
reg spi_tick;

always @(posedge clk) begin
    if (!resetn) begin
        div_cnt <= 0;
        spi_tick <= 0;
    end else begin
        if (div_cnt == clk_div) begin
            div_cnt <= 0;
            spi_tick <= 1;
        end else begin
            div_cnt <= div_cnt + 1;
            spi_tick <= 0;
        end
    end
end

reg [2:0] bit_cnt;
reg [7:0] shift_tx;
reg [7:0] shift_rx;
reg busy;

always @(posedge clk) begin
    if (!resetn) begin
        sd_clk <= 0;
        busy <= 0;
        tx_ready <= 1;
        rx_valid <= 0;
        sd_cs <= 1;
    end else begin

        rx_valid <= 0;

        if (tx_valid && tx_ready) begin
            busy <= 1;
            tx_ready <= 0;
            bit_cnt <= 7;
            shift_tx <= tx_data;
            shift_rx <= 0;
            sd_cs <= 0;
        end

        if (busy && spi_tick) begin
            sd_clk <= ~sd_clk;

            if (sd_clk == 0) begin
                sd_mosi <= shift_tx[bit_cnt];
            end else begin
                shift_rx[bit_cnt] <= sd_miso;

                if (bit_cnt == 0) begin
                    busy <= 0;
                    tx_ready <= 1;
                    rx_data <= shift_rx;
                    rx_valid <= 1;
                    sd_cs <= 1;
                end else begin
                    bit_cnt <= bit_cnt - 1;
                end
            end
        end
    end
end

endmodule