`timescale 1ns / 1ps

module simple_spi_master (
    input    clk,
    input    resetn,
    input    start,
    input    [7:0] tx_data,
    input    [15:0] clkdiv,
    input    cs_n,
    output reg [7:0] rx_data,
    output reg busy,
    output reg done,
    output spi_sck,
    output spi_mosi,
    input spi_miso,
    output spi_cs_n
);

reg [15:0] divcnt;
reg [2:0] bitpos;
reg sck_reg;
reg mosi_reg;
reg [7:0] tx_latch;
reg [7:0] rx_shift;

assign spi_sck = busy ? sck_reg : 1'b0;
assign spi_mosi = mosi_reg;
assign spi_cs_n = cs_n;

always @(posedge clk) begin
    if (!resetn) begin
        divcnt <= 0;
        bitpos <= 0;
        sck_reg <= 0;
	mosi_reg <= 1'b1;
	tx_latch <= 8'hFF;
	rx_shift <= 8'h00;
        rx_data <= 8'hFF;
        busy <= 0;
        done <= 0;
    end else begin
        done <= 0;

        if (start && !busy) begin
            busy <= 1'b1;
            sck_reg <= 1'b0;
            divcnt <= clkdiv;
            bitpos <= 3'd7;
            tx_latch <= tx_data;
            rx_shift <= 8'h00;
            mosi_reg <= tx_data[7];
        end else if (busy) begin
            if (divcnt != 0) begin
                divcnt <= divcnt - 1'b1;
            end else begin
                divcnt <= clkdiv;
                if (!sck_reg) begin
                    sck_reg <= 1'b1;
                    rx_shift[bitpos] <= spi_miso;
                end else begin
                    sck_reg <= 1'b0;
                    if (bitpos == 0) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        rx_data <= rx_shift;
                        mosi_reg <= 1'b1;
                    end else begin
                        bitpos <= bitpos - 1'b1;
                        mosi_reg <= tx_latch[bitpos-1'b1];
                    end
                end
            end
        end
    end
end

endmodule
