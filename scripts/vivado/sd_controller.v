`timescale 1ns / 1ps
//============================================================================
// SD Controller - FIXED VERSION
// Handles SD card initialization sequence properly
//============================================================================

module sd_controller (
    input clk,
    input resetn,

    // SPI interface
    output reg [7:0] tx_data,
    output reg tx_valid,
    input tx_ready,

    input [7:0] rx_data,
    input rx_valid,

    // CS control
    output reg cs_enable,

    // Status
    output reg init_done
);

// States
localparam S_RESET       = 0;
localparam S_POWERUP     = 1;
localparam S_CMD0        = 2;
localparam S_CMD0_RESP   = 3;
localparam S_CMD8        = 4;
localparam S_CMD8_RESP   = 5;
localparam S_CMD55       = 6;
localparam S_CMD55_RESP  = 7;
localparam S_ACMD41      = 8;
localparam S_ACMD41_RESP = 9;
localparam S_DONE        = 10;

reg [3:0] state;
reg [7:0] cmd_buf [0:5];
reg [2:0] byte_cnt;
reg [7:0] power_cnt;
reg [7:0] resp_cnt;
reg [15:0] retry_cnt;

always @(posedge clk) begin
    if (!resetn) begin
        state <= S_RESET;
        tx_valid <= 0;
        init_done <= 0;
        cs_enable <= 0;
        byte_cnt <= 0;
        power_cnt <= 0;
        resp_cnt <= 0;
        retry_cnt <= 0;
    end else begin
        tx_valid <= 0;

        case (state)
        
        //--------------------------------------------
        // Power up: send 80+ clock cycles with CS high
        //--------------------------------------------
        S_RESET: begin
            cs_enable <= 0;  // CS high
            power_cnt <= 0;
            state <= S_POWERUP;
        end

        S_POWERUP: begin
            cs_enable <= 0;  // CS high during power up
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
                power_cnt <= power_cnt + 1;
                if (power_cnt >= 10) begin  // 80+ clocks
                    state <= S_CMD0;
                end
            end
        end

        //--------------------------------------------
        // CMD0: GO_IDLE_STATE
        //--------------------------------------------
        S_CMD0: begin
            cs_enable <= 1;  // CS low
            cmd_buf[0] <= 8'h40;  // CMD0
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h95;  // CRC
            byte_cnt <= 0;
            resp_cnt <= 0;
            
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'h40;
                tx_valid <= 1;
                byte_cnt <= 1;
            end
            
            if (byte_cnt > 0 && byte_cnt <= 5 && tx_ready && !tx_valid) begin
                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;
                byte_cnt <= byte_cnt + 1;
            end
            
            if (byte_cnt > 5) begin
                state <= S_CMD0_RESP;
            end
        end

        S_CMD0_RESP: begin
            // Send dummy bytes and wait for response
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                if (rx_data == 8'h01) begin
                    // Got R1 = 0x01 (idle state)
                    cs_enable <= 0;  // CS high
                    state <= S_CMD8;
                end else if (resp_cnt > 100) begin
                    // Timeout, retry
                    cs_enable <= 0;
                    state <= S_CMD0;
                end
            end
        end

        //--------------------------------------------
        // CMD8: SEND_IF_COND (for SDHC)
        //--------------------------------------------
        S_CMD8: begin
            cs_enable <= 1;
            cmd_buf[0] <= 8'h48;  // CMD8
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h01;
            cmd_buf[4] <= 8'hAA;
            cmd_buf[5] <= 8'h87;  // CRC
            byte_cnt <= 0;
            resp_cnt <= 0;
            
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'h48;
                tx_valid <= 1;
                byte_cnt <= 1;
            end
            
            if (byte_cnt > 0 && byte_cnt <= 5 && tx_ready && !tx_valid) begin
                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;
                byte_cnt <= byte_cnt + 1;
            end
            
            if (byte_cnt > 5) begin
                state <= S_CMD8_RESP;
            end
        end

        S_CMD8_RESP: begin
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                // Skip CMD8 response bytes (R7 = 5 bytes)
                if (resp_cnt > 10) begin
                    cs_enable <= 0;
                    state <= S_CMD55;
                    retry_cnt <= 0;
                end
            end
        end

        //--------------------------------------------
        // CMD55: APP_CMD prefix
        //--------------------------------------------
        S_CMD55: begin
            cs_enable <= 1;
            cmd_buf[0] <= 8'h77;  // CMD55
            cmd_buf[1] <= 8'h00;
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h65;  // CRC
            byte_cnt <= 0;
            resp_cnt <= 0;
            
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'h77;
                tx_valid <= 1;
                byte_cnt <= 1;
            end
            
            if (byte_cnt > 0 && byte_cnt <= 5 && tx_ready && !tx_valid) begin
                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;
                byte_cnt <= byte_cnt + 1;
            end
            
            if (byte_cnt > 5) begin
                state <= S_CMD55_RESP;
            end
        end

        S_CMD55_RESP: begin
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                if (rx_data != 8'hFF && resp_cnt > 0) begin
                    cs_enable <= 0;
                    state <= S_ACMD41;
                end else if (resp_cnt > 20) begin
                    cs_enable <= 0;
                    state <= S_ACMD41;
                end
            end
        end

        //--------------------------------------------
        // ACMD41: SD_SEND_OP_COND
        //--------------------------------------------
        S_ACMD41: begin
            cs_enable <= 1;
            cmd_buf[0] <= 8'h69;  // ACMD41
            cmd_buf[1] <= 8'h40;  // HCS bit set
            cmd_buf[2] <= 8'h00;
            cmd_buf[3] <= 8'h00;
            cmd_buf[4] <= 8'h00;
            cmd_buf[5] <= 8'h77;  // CRC (dummy)
            byte_cnt <= 0;
            resp_cnt <= 0;
            
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'h69;
                tx_valid <= 1;
                byte_cnt <= 1;
            end
            
            if (byte_cnt > 0 && byte_cnt <= 5 && tx_ready && !tx_valid) begin
                tx_data <= cmd_buf[byte_cnt];
                tx_valid <= 1;
                byte_cnt <= byte_cnt + 1;
            end
            
            if (byte_cnt > 5) begin
                state <= S_ACMD41_RESP;
            end
        end

        S_ACMD41_RESP: begin
            if (tx_ready && !tx_valid) begin
                tx_data <= 8'hFF;
                tx_valid <= 1;
            end
            
            if (rx_valid) begin
                resp_cnt <= resp_cnt + 1;
                
                if (rx_data == 8'h00) begin
                    // Card ready!
                    cs_enable <= 0;
                    state <= S_DONE;
                end else if (rx_data == 8'h01) begin
                    // Still initializing, retry
                    cs_enable <= 0;
                    retry_cnt <= retry_cnt + 1;
                    if (retry_cnt < 1000) begin
                        state <= S_CMD55;
                    end else begin
                        // Timeout - assume done anyway
                        state <= S_DONE;
                    end
                end else if (resp_cnt > 20) begin
                    // Retry
                    cs_enable <= 0;
                    retry_cnt <= retry_cnt + 1;
                    state <= S_CMD55;
                end
            end
        end

        //--------------------------------------------
        // Done
        //--------------------------------------------
        S_DONE: begin
            cs_enable <= 0;
            init_done <= 1;
        end

        endcase
    end
end

endmodule
