`timescale 1ns / 1ps

module sd_bootloader(

    input clk,
    input resetn,

    output reg cpu_resetn,

    // RAM write port
    output reg [31:0] ram_addr,
    output reg [7:0]  ram_wdata,
    output reg        ram_we,

    // sd_controller
    output reg init_start,
    input init_done,

    // sd_read_block
    output reg read_start,
    output reg [31:0] block_addr,
    input block_done,

    input [7:0] data_in,
    input data_valid

);

localparam S_RESET      = 0;
localparam S_INIT       = 1;
localparam S_WAIT_INIT  = 2;
localparam S_READ_BLOCK = 3;
localparam S_COPY_DATA  = 4;
localparam S_NEXT_BLOCK = 5;
localparam S_BOOT_DONE  = 6;

reg [2:0] state;

reg [15:0] byte_count;
reg [7:0] sector_count;

localparam FW_BASE_ADDR = 32'h00002000;
localparam SD_BASE_SECTOR = 32'd100;
localparam FW_SECTORS = 32;

always @(posedge clk) begin

    if(!resetn) begin
        state <= S_RESET;
        cpu_resetn <= 0;
        ram_we <= 0;
    end

    else begin

        ram_we <= 0;

        case(state)

        //------------------------------------
        S_RESET:
        begin
            init_start <= 1;
            state <= S_INIT;
        end

        //------------------------------------
        S_INIT:
        begin
            init_start <= 0;
            state <= S_WAIT_INIT;
        end

        //------------------------------------
        S_WAIT_INIT:
        begin
            if(init_done) begin
                sector_count <= 0;
                ram_addr <= FW_BASE_ADDR;
                state <= S_READ_BLOCK;
            end
        end

        //------------------------------------
        S_READ_BLOCK:
        begin
            block_addr <= SD_BASE_SECTOR + sector_count;
            read_start <= 1;
            byte_count <= 0;
            state <= S_COPY_DATA;
        end

        //------------------------------------
        S_COPY_DATA:
        begin
            read_start <= 0;

            if(data_valid) begin

                ram_wdata <= data_in;
                ram_we <= 1;

                ram_addr <= ram_addr + 1;
                byte_count <= byte_count + 1;

                if(byte_count == 511)
                    state <= S_NEXT_BLOCK;
            end
        end

        //------------------------------------
        S_NEXT_BLOCK:
        begin
            sector_count <= sector_count + 1;

            if(sector_count == FW_SECTORS-1)
                state <= S_BOOT_DONE;
            else
                state <= S_READ_BLOCK;
        end

        //------------------------------------
        S_BOOT_DONE:
        begin
            cpu_resetn <= 1;
        end

        endcase
    end
end

endmodule