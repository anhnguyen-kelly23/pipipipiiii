`timescale 1ns / 1ps
//============================================================================
// SD Read Block - FIXED VERSION
// Reads a 512-byte block from SD card
//============================================================================

module sd_read_block (
    input clk,
    input resetn,

    // Control
    input start,
    input [31:0] block_addr,

    // SPI interface
    output reg [7:0] tx_data,
    output reg tx_valid,
    input tx_ready,

    input [7:0] rx_data,
    input rx_valid,

    // CS control
    output reg cs_enable,

    // Data output
    output reg [7:0] data_out,
    output reg data_valid,

    // Status
    output reg block_done
);

// States
localparam S_IDLE       = 0;
localparam S_CMD17_SEND = 1;
localparam S_WAIT_R1    = 2;
localparam S_WAIT_TOKEN = 3;
localparam S_READ_DATA  = 4;
localparam S_READ_CRC   = 5;
localparam S_DONE       = 6;

reg [2:0] state;
reg [7:0] cmd_buf [0:5];
reg [2:0] byte_cnt;
reg [8:0] data_cnt;     // 0-511
reg [1:0] crc_cnt;
reg [7:0] resp_cnt;

always @(posedge clk) begin
    if (!resetn) begin
        state <= S_IDLE;
        tx_valid <= 0;
        data_valid <= 0;
        block_done <= 0;
        cs_enable <= 0;
        byte_cnt <= 0;
        data_cnt <= 0;
        crc_cnt <= 0;
        resp_cnt <= 0;
    end else begin
        tx_valid <= 0;
        data_valid <= 0;
        block_done <= 0;

        case (state)

        //--------------------------------------------
        S_IDLE: begin
            cs_enable <= 0;
            if (start) begin
                cs_enable <= 1;
                // CMD17: READ_SINGLE_BLOCK
                cmd_buf[0] <= 8'h51;  // CMD17
                cmd_buf[1] <= block_addr[31:24];
                cmd_buf[2] <= block_addr[23:16];
                cmd_buf[3] <= block_addr[15:8];
                cmd_buf[4] <= block_addr[7:0];
                cmd_buf[5] <= 8'hFF;  // Dummy CRC
                byte_cnt <= 0;
                state <= S_CMD17_SEND;
            end
        end

        //--------------------------------------------
        S_CMD17_SEND: begin
            cs_enable <= 1;
            if (tx_ready && !tx_valid) begin
                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;
                byte_cnt <= byte_cnt + 1;
                if (byte_cnt >= 5) begin
                    resp_cnt <= 0;
                    state <= S_WAIT_R1;
                end
            end
        end

        //--------------------------------------------
        S_WAIT_R1: begin
            // Send dummy bytes and wait for R1 response (not 0xFF)
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                if (rx_data != 8'hFF) begin
                    // Got R1 response
                    if (rx_data == 8'h00) begin
                        resp_cnt <= 0;
                        state <= S_WAIT_TOKEN;
                    end else begin
                        // Error response
                        cs_enable <= 0;
                        state <= S_IDLE;
                    end
                end else if (resp_cnt > 100) begin
                    // Timeout
                    cs_enable <= 0;
                    state <= S_IDLE;
                end
            end
        end

        //--------------------------------------------
        S_WAIT_TOKEN: begin
            // Wait for data token 0xFE
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                if (rx_data == 8'hFE) begin
                    // Data token received - start reading data
                    data_cnt <= 0;
                    state <= S_READ_DATA;
                end else if (resp_cnt > 200) begin
                    // Timeout
                    cs_enable <= 0;
                    state <= S_IDLE;
                end
            end
        end

        //--------------------------------------------
        S_READ_DATA: begin
            // Read 512 bytes of data
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                data_out <= rx_data;
                data_valid <= 1;
                data_cnt <= data_cnt + 1;
                
                if (data_cnt >= 511) begin
                    crc_cnt <= 0;
                    state <= S_READ_CRC;
                end
            end
        end

        //--------------------------------------------
        S_READ_CRC: begin
            // Read 2 CRC bytes (ignore them)
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                crc_cnt <= crc_cnt + 1;
                if (crc_cnt >= 1) begin
                    state <= S_DONE;
                end
            end
        end

        //--------------------------------------------
        S_DONE: begin
            cs_enable <= 0;
            block_done <= 1;
            state <= S_IDLE;
        end

        endcase
    end
end

endmodule
