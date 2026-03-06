`timescale 1ns / 1ps

module spi_arbiter(

    input clk,
    input resetn,

    // select
    input init_phase,

    // controller interface
    input  [7:0] ctrl_tx_data,
    input        ctrl_tx_valid,
    output       ctrl_tx_ready,

    output [7:0] ctrl_rx_data,
    output       ctrl_rx_valid,

    // reader interface
    input  [7:0] read_tx_data,
    input        read_tx_valid,
    output       read_tx_ready,

    output [7:0] read_rx_data,
    output       read_rx_valid,

    // SPI master
    output [7:0] spi_tx_data,
    output       spi_tx_valid,
    input        spi_tx_ready,

    input  [7:0] spi_rx_data,
    input        spi_rx_valid
);

assign spi_tx_data  = init_phase ? ctrl_tx_data  : read_tx_data;
assign spi_tx_valid = init_phase ? ctrl_tx_valid : read_tx_valid;

assign ctrl_tx_ready = init_phase ? spi_tx_ready : 1'b0;
assign read_tx_ready = init_phase ? 1'b0 : spi_tx_ready;

assign ctrl_rx_data  = spi_rx_data;
assign read_rx_data  = spi_rx_data;

assign ctrl_rx_valid = init_phase ? spi_rx_valid : 1'b0;
assign read_rx_valid = init_phase ? 1'b0 : spi_rx_valid;

endmodule