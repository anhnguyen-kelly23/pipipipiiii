`timescale 1ns / 1ps

module sd_read_block(

    input clk,
    input resetn,

    input start,
    input [31:0] block_addr,

    output reg [7:0] tx_data,
    output reg tx_valid,
    input tx_ready,

    input [7:0] rx_data,
    input rx_valid,

    output reg [7:0] data_out,
    output reg data_valid,

    output reg block_done

);

localparam S_IDLE       = 0;
localparam S_CMD17      = 1;
localparam S_CMD17_SEND = 2;
localparam S_WAIT_R1    = 3;
localparam S_WAIT_TOKEN = 4;
localparam S_READ_DATA  = 5;
localparam S_READ_CRC   = 6;
localparam S_DONE       = 7;

reg [3:0] state;

reg [7:0] cmd_buf [0:5];
reg [2:0] byte_cnt;

reg [8:0] data_cnt;
reg [1:0] crc_cnt;

always @(posedge clk) begin

    if(!resetn) begin
        state <= S_IDLE;
        tx_valid <= 0;
        data_valid <= 0;
        block_done <= 0;
    end

    else begin

        tx_valid <= 0;
        data_valid <= 0;
        block_done <= 0;

        case(state)

        //----------------------------------
        S_IDLE:
        begin
            if(start) begin

                cmd_buf[0] <= 8'h51;

                cmd_buf[1] <= block_addr[31:24];
                cmd_buf[2] <= block_addr[23:16];
                cmd_buf[3] <= block_addr[15:8];
                cmd_buf[4] <= block_addr[7:0];

                cmd_buf[5] <= 8'hFF;

                byte_cnt <= 0;
                state <= S_CMD17;
            end
        end

        //----------------------------------
        S_CMD17:
        begin
            if(tx_ready) begin

                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;

                byte_cnt <= byte_cnt + 1;

                if(byte_cnt == 5) begin
                    state <= S_WAIT_R1;
                end
            end
        end

        //----------------------------------
        S_WAIT_R1:
        begin
            if(rx_valid) begin
                if(rx_data != 8'hFF)
                    state <= S_WAIT_TOKEN;
            end
        end

        //----------------------------------
        S_WAIT_TOKEN:
        begin
            if(rx_valid) begin
                if(rx_data == 8'hFE) begin
                    data_cnt <= 0;
                    state <= S_READ_DATA;
                end
            end
        end

        //----------------------------------
        S_READ_DATA:
        begin
            if(rx_valid) begin

                data_out <= rx_data;
                data_valid <= 1;

                data_cnt <= data_cnt + 1;

                if(data_cnt == 511) begin
                    crc_cnt <= 0;
                    state <= S_READ_CRC;
                end
            end
        end

        //----------------------------------
        S_READ_CRC:
        begin
            if(rx_valid) begin
                crc_cnt <= crc_cnt + 1;

                if(crc_cnt == 1)
                    state <= S_DONE;
            end
        end

        //----------------------------------
        S_DONE:
        begin
            block_done <= 1;
            state <= S_IDLE;
        end

        endcase
    end
end

endmodule