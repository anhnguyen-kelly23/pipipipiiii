`timescale 1ns / 1ps
//============================================================================
// SD CPU Interface
// Cho phép CPU (PicoRV32) điều khiển việc đọc SD card thông qua memory-mapped registers
//
// Memory Map (base: 0x7000_0000):
//   0x00 [R]   : Status      - bit0: init_done, bit1: block_done, bit2: data_valid, bit3: fifo_empty
//   0x04 [R/W] : Block Addr  - Địa chỉ sector cần đọc (32-bit)
//   0x08 [W]   : Control     - bit0: start_read (tự động clear)
//   0x0C [R]   : Data        - Đọc 1 byte từ FIFO (auto-advance)
//   0x10 [R]   : Byte Count  - Số bytes đã đọc trong block hiện tại
//============================================================================

module sd_cpu_interface (
    input         clk,
    input         resetn,
    
    // CPU Memory Interface
    input         mem_valid,
    input  [31:0] mem_addr,
    input  [31:0] mem_wdata,
    input  [ 3:0] mem_wstrb,
    output reg    mem_ready,
    output reg [31:0] mem_rdata,
    
    // SD Hardware Interface
    input         init_done,      // Từ sd_controller
    output reg    read_start,     // Đến sd_read_block
    output reg [31:0] block_addr, // Đến sd_read_block
    input         block_done,     // Từ sd_read_block
    input  [ 7:0] data_in,        // Từ sd_read_block
    input         data_valid      // Từ sd_read_block
);

    // Base address check
    localparam SD_BASE = 32'h7000_0000;
    wire addr_match = (mem_addr[31:8] == SD_BASE[31:8]);
    wire [7:0] reg_offset = mem_addr[7:0];
    
    // FIFO để buffer data từ SD (512 bytes per block)
    reg [7:0] fifo [0:511];
    reg [9:0] fifo_wr_ptr;
    reg [9:0] fifo_rd_ptr;
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire [9:0] fifo_count = fifo_wr_ptr - fifo_rd_ptr;
    
    // State
    reg reading;
    reg block_done_latch;
    
    // Ghi data vào FIFO khi data_valid
    always @(posedge clk) begin
        if (!resetn) begin
            fifo_wr_ptr <= 0;
        end else if (read_start) begin
            fifo_wr_ptr <= 0;  // Reset FIFO khi bắt đầu đọc block mới
        end else if (data_valid && reading) begin
            fifo[fifo_wr_ptr[8:0]] <= data_in;
            fifo_wr_ptr <= fifo_wr_ptr + 1;
        end
    end
    
    // Xử lý block_done
    always @(posedge clk) begin
        if (!resetn) begin
            block_done_latch <= 0;
            reading <= 0;
        end else begin
            if (read_start) begin
                reading <= 1;
                block_done_latch <= 0;
            end
            if (block_done && reading) begin
                block_done_latch <= 1;
                reading <= 0;
            end
        end
    end
    
    // CPU Memory Access
    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 0;
            mem_rdata <= 0;
            read_start <= 0;
            block_addr <= 0;
            fifo_rd_ptr <= 0;
        end else begin
            mem_ready <= 0;
            read_start <= 0;
            
            if (mem_valid && !mem_ready && addr_match) begin
                mem_ready <= 1;
                
                if (|mem_wstrb) begin
                    // Write
                    case (reg_offset)
                        8'h04: block_addr <= mem_wdata;
                        8'h08: begin
                            if (mem_wdata[0] && init_done && !reading) begin
                                read_start <= 1;
                                fifo_rd_ptr <= 0;  // Reset read pointer
                            end
                        end
                    endcase
                end else begin
                    // Read
                    case (reg_offset)
                        8'h00: mem_rdata <= {28'b0, fifo_empty, data_valid, block_done_latch, init_done};
                        8'h04: mem_rdata <= block_addr;
                        8'h0C: begin
                            mem_rdata <= {24'b0, fifo[fifo_rd_ptr[8:0]]};
                            if (!fifo_empty)
                                fifo_rd_ptr <= fifo_rd_ptr + 1;
                        end
                        8'h10: mem_rdata <= {22'b0, fifo_count};
                        default: mem_rdata <= 32'hDEADBEEF;
                    endcase
                end
            end
        end
    end

endmodule
