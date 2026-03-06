`timescale 1ns / 1ps

module sd_controller(

    input clk,
    input resetn,

    output reg [7:0] tx_data,
    output reg tx_valid,
    input tx_ready,

    input [7:0] rx_data,
    input rx_valid,

    output reg init_done

);

localparam S_RESET       = 0;
localparam S_POWERUP     = 1;
localparam S_CMD0        = 2;
localparam S_CMD0_WAIT   = 3;
localparam S_CMD8        = 4;
localparam S_CMD8_WAIT   = 5;
localparam S_CMD55       = 6;
localparam S_CMD55_WAIT  = 7;
localparam S_ACMD41      = 8;
localparam S_ACMD41_WAIT = 9;
localparam S_READY       = 10;

reg [3:0] state;

reg [7:0] cmd_buf [0:5];
reg [2:0] byte_cnt;
reg [7:0] power_cnt;

always @(posedge clk) begin

    if(!resetn) begin
        state <= S_RESET;
        tx_valid <= 0;
        init_done <= 0;
        byte_cnt <= 0;
        power_cnt <= 0;
    end

    else begin

        tx_valid <= 0;

        case(state)

        //------------------------------------------------
        S_RESET:
        begin
            power_cnt <= 0;
            state <= S_POWERUP;
        end

        //------------------------------------------------
        // send ≥80 clock cycles (10 bytes of 0xFF)
        S_POWERUP:
        begin
            if(tx_ready) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;

                power_cnt <= power_cnt + 1;

                if(power_cnt == 10)
                    state <= S_CMD0;
            end
        end

        //------------------------------------------------
        // CMD0 : GO_IDLE_STATE
        S_CMD0:
        begin
            cmd_buf[0] <= 8'h40;
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h95;

            byte_cnt <= 0;
            state <= S_CMD0_WAIT;
        end

        S_CMD0_WAIT:
        begin
            if(tx_ready) begin

                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;

                byte_cnt <= byte_cnt + 1;

                if(byte_cnt == 5) begin
                    byte_cnt <= 0;
                    state <= S_CMD8;
                end
            end
        end

        //------------------------------------------------
        // CMD8 : SEND_IF_COND
        S_CMD8:
        begin
            cmd_buf[0] <= 8'h48;
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h01;
            cmd_buf[4] <= 8'hAA;
            cmd_buf[5] <= 8'h87;

            byte_cnt <= 0;
            state <= S_CMD8_WAIT;
        end

        S_CMD8_WAIT:
        begin
            if(tx_ready) begin

                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;

                byte_cnt <= byte_cnt + 1;

                if(byte_cnt == 5) begin
                    byte_cnt <= 0;
                    state <= S_CMD55;
                end
            end
        end

        //------------------------------------------------
        // CMD55 : APP_CMD
        S_CMD55:
        begin
            cmd_buf[0] <= 8'h77;
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h65;

            byte_cnt <= 0;
            state <= S_CMD55_WAIT;
        end

        S_CMD55_WAIT:
        begin
            if(tx_ready) begin

                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;

                byte_cnt <= byte_cnt + 1;

                if(byte_cnt == 5) begin
                    byte_cnt <= 0;
                    state <= S_ACMD41;
                end
            end
        end

        //------------------------------------------------
        // ACMD41 : initialize card
        S_ACMD41:
        begin
            cmd_buf[0] <= 8'h69;
            cmd_buf[1] <= 8'h40;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h77;

            byte_cnt <= 0;
            state <= S_ACMD41_WAIT;
        end

        S_ACMD41_WAIT:
        begin
            if(tx_ready) begin

                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;

                byte_cnt <= byte_cnt + 1;

                if(byte_cnt == 5) begin
                    byte_cnt <= 0;
                end
            end

            // parse response
            if(rx_valid) begin
                if(rx_data == 8'h00)
                    state <= S_READY;
                else
                    state <= S_CMD55; // repeat CMD55+ACMD41
            end
        end

        //------------------------------------------------
        S_READY:
        begin
            init_done <= 1;
        end

        endcase
    end
end

endmodule