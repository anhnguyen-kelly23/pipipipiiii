`timescale 1 ns / 1 ps

// ============================================================
// system.v — PicoRV32 SoC, ARTY A7-100T
//
// MEMORY MAP
//   0x0000_0000 – 0x0000_0FFF  Boot BRAM  4 KB  (bootloader, RO)
//   0x0001_0000 – 0x0001_FFFF  App  BRAM 64 KB  (loaded from SD)
//   0x1000_0000                LED  out_byte     W
//   0x1000_0004                UART TX Data      W
//   0x1000_0008                UART RX Data      R
//   0x1000_000C                UART Status       R  [1]=rx_valid [0]=tx_ready
//   0x1000_0010                UART Baud Divider R/W
//   0x2000_0000                Switches          R
//   0x2000_0004                Buttons           R
//   0x3000_0000 – 0x3000_0060  TinyJAMBU         R/W
//   0x4000_0000 – 0x4000_0074  Xoodyak           R/W
//   0x5000_0000 – 0x5000_0078  GIFT-COFB         R/W
//   0x6000_0000 – 0x6000_000C  SD SPI Master     R/W
//
// SD SPI REGISTERS
//   0x6000_0000  DATA   W=tx byte (starts xfer)  R=last rx byte
//   0x6000_0004  STATUS R  [2]=cs_n [1]=busy [0]=done_sticky
//   0x6000_0008  CTRL   W  [0]=cs_n
//   0x6000_000C  CLKDIV W  [15:0] half-period divider
//                          199 → ~250 kHz (init), 1 → 25 MHz (run)
//
// UART TIMING  (100 MHz clock, 115200 baud)
//   868 clocks/bit × 10 bits = 8680 clocks/byte
//   tx_countdown = 9000  (≥ 8680, safe margin)
//
// TinyJAMBU  base 0x3000_0000
//   0x00-0x0C KEY[3:0]   0x10-0x18 NONCE[2:0]
//   0x1C-0x28 AD[3:0]    0x2C-0x38 DIN[3:0]
//   0x3C-0x40 TAGIN[1:0] 0x44 CTRL  0x48 STATUS
//   0x4C-0x58 DOUT[3:0]  0x5C-0x60 TAGOUT[1:0]
//   CTRL: [18:16]=sel_type [12:8]=ad_len [4:0]=data_len
//
// Xoodyak    base 0x4000_0000
//   0x00-0x0C KEY[3:0]   0x10-0x1C NONCE[3:0]
//   0x20-0x2C AD[3:0]    0x30-0x3C DIN[3:0]
//   0x40-0x4C TAGIN[3:0] 0x50 CTRL  0x54 STATUS
//   0x58-0x64 DOUT[3:0]  0x68-0x74 TAGOUT[3:0]
//   CTRL: [18:16]=sel_type [12:8]=ad_len [4:0]=data_len
//
// GIFT-COFB  base 0x5000_0000
//   0x00-0x0C KEY[3:0]   0x10-0x1C NONCE[3:0]
//   0x20-0x2C AD[3:0]    0x30-0x3C DIN[3:0]
//   0x40-0x4C TAGIN[3:0] 0x50 CTRL  0x54 STATUS
//   0x58-0x64 DOUT[3:0]  0x68-0x74 TAGOUT[3:0]
//   0x78 ACK  W  [1]=ad_ack [0]=msg_ack
//   CTRL: [16]=decrypt [15:8]=ad_len [7:0]=data_len
//   STATUS: [3]=ad_req [2]=msg_req [1]=done [0]=valid
// ============================================================

module system (
    input            clk,
    input            resetn_btn,
    output           trap,
    output reg [7:0] out_byte,
    output reg       out_byte_en,

    input      [3:0] sw,
    input      [3:0] btn,

    output           uart_tx,
    input            uart_rx,

    output           sd_cs_n,
    output           sd_sck,
    output           sd_mosi,
    input            sd_miso
);

    parameter FAST_MEMORY = 1;
    parameter BOOT_SIZE   = 1024;   // 4 KB in words
    parameter APP_SIZE    = 16384;  // 64 KB in words

    // --------------------------------------------------------
    // Power-on reset
    // --------------------------------------------------------
    reg [5:0] reset_cnt    = 0;
    reg [2:0] resetn_sync  = 3'b000;

    always @(posedge clk)
        resetn_sync <= {resetn_sync[1:0], resetn_btn};

    always @(posedge clk) begin
        if (!resetn_sync[2] && (&reset_cnt))
            reset_cnt <= 0;
        else if (!(&reset_cnt))
            reset_cnt <= reset_cnt + 1;
    end

    wire resetn = &reset_cnt;

    // --------------------------------------------------------
    // Switch / Button synchroniser
    // --------------------------------------------------------
    reg [3:0] sw_sync1,  sw_sync2;
    reg [3:0] btn_sync1, btn_sync2;

    always @(posedge clk) begin
        sw_sync1  <= sw;        sw_sync2  <= sw_sync1;
        btn_sync1 <= btn;       btn_sync2 <= btn_sync1;
    end

    // --------------------------------------------------------
    // UART
    // --------------------------------------------------------
    wire        uart_dat_wait;
    wire [31:0] uart_dat_do;
    wire [31:0] uart_div_do;
    wire uart_rx_valid = (uart_dat_do != 32'hFFFF_FFFF);

    reg        uart_we;
    reg        uart_rx_rd;
    reg  [7:0] uart_tx_data;
    reg  [3:0] uart_div_we;
    reg [31:0] uart_div_di;
    reg        tx_busy;
    reg [15:0] tx_countdown;
    wire uart_tx_ready = !tx_busy;

    simpleuart #(.DEFAULT_DIV(868)) uart_inst (
        .clk        (clk),
        .resetn     (resetn),
        .ser_tx     (uart_tx),
        .ser_rx     (uart_rx),
        .reg_div_we (uart_div_we),
        .reg_div_di (uart_div_di),
        .reg_div_do (uart_div_do),
        .reg_dat_we (uart_we),
        .reg_dat_re (uart_rx_rd),
        .reg_dat_di ({24'b0, uart_tx_data}),
        .reg_dat_do (uart_dat_do),
        .reg_dat_wait(uart_dat_wait)
    );

    // --------------------------------------------------------
    // SD SPI Master
    // --------------------------------------------------------
    reg  [7:0] sdspi_tx_data;
    reg [15:0] sdspi_clkdiv;
    reg        sdspi_start;
    reg        sdspi_cs_n_reg;
    reg        sdspi_done_sticky;
    reg  [7:0] sdspi_rx_data_reg;
    wire [7:0] sdspi_rx_data;
    wire       sdspi_busy;
    wire       sdspi_done;

    simple_spi_master u_sdspi (
        .clk      (clk),
        .resetn   (resetn),
        .start    (sdspi_start),
        .tx_data  (sdspi_tx_data),
        .clkdiv   (sdspi_clkdiv),
        .cs_n     (sdspi_cs_n_reg),
        .rx_data  (sdspi_rx_data),
        .busy     (sdspi_busy),
        .done     (sdspi_done),
        .spi_sck  (sd_sck),
        .spi_mosi (sd_mosi),
        .spi_miso (sd_miso),
        .spi_cs_n (sd_cs_n)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            sdspi_done_sticky <= 0;
            sdspi_rx_data_reg <= 8'hFF;
        end else begin
            if (sdspi_start)  sdspi_done_sticky <= 0;
            if (sdspi_done) begin
                sdspi_done_sticky <= 1;
                sdspi_rx_data_reg <= sdspi_rx_data;
            end
        end
    end

    // --------------------------------------------------------
    // TinyJAMBU (0x3000_0000)
    // --------------------------------------------------------
    reg [127:0] jb_key;
    reg [ 95:0] jb_nonce;
    reg [127:0] jb_ad, jb_data_in;
    reg [ 63:0] jb_tag_in;
    reg [  4:0] jb_ad_length, jb_data_length;
    reg [  2:0] jb_sel_type;
    reg         jb_ena;
    reg         jb_done_sticky, jb_valid_sticky;

    wire [127:0] jb_data_out;
    wire [ 63:0] jb_tag_out;
    wire         jb_valid, jb_done;

    tinyjambu_core u_jambu (
        .clk        (clk),      .rst_n      (resetn),
        .ena        (jb_ena),   .sel_type   (jb_sel_type),
        .key        (jb_key),   .nonce      (jb_nonce),
        .ad         (jb_ad),    .ad_length  (jb_ad_length),
        .data_length(jb_data_length),
        .data_in    (jb_data_in),.tag_in    (jb_tag_in),
        .data_out   (jb_data_out),.tag      (jb_tag_out),
        .valid      (jb_valid), .done       (jb_done)
    );

    always @(posedge clk) begin
        if      (!resetn) begin jb_done_sticky<=0; jb_valid_sticky<=0; end
        else if (jb_ena)  begin jb_done_sticky<=0; jb_valid_sticky<=0; end
        else if (jb_done) begin jb_done_sticky<=1; jb_valid_sticky<=jb_valid; end
    end

    // --------------------------------------------------------
    // Xoodyak (0x4000_0000)
    // --------------------------------------------------------
    reg [127:0] xd_key, xd_nonce, xd_ad, xd_data_in, xd_tag_in;
    reg [  4:0] xd_ad_length, xd_data_length;
    reg [  2:0] xd_sel_type;
    reg         xd_ena;
    reg         xd_done_sticky, xd_valid_sticky;

    wire [127:0] xd_data_out, xd_tag_out;
    wire         xd_valid, xd_done;

    xoodyakcore u_xoodyak (
        .clk        (clk),      .rst_n      (resetn),
        .ena        (xd_ena),   .restart    (1'b0),
        .sel_type   (xd_sel_type),
        .key        (xd_key),   .nonce      (xd_nonce),
        .ad         (xd_ad),    .ad_length  (xd_ad_length),
        .data_length(xd_data_length),
        .data_in    (xd_data_in),.tag_in    (xd_tag_in),
        .valid      (xd_valid), .tag        (xd_tag_out),
        .data_out   (xd_data_out),.done     (xd_done)
    );

    always @(posedge clk) begin
        if      (!resetn) begin xd_done_sticky<=0; xd_valid_sticky<=0; end
        else if (xd_ena)  begin xd_done_sticky<=0; xd_valid_sticky<=0; end
        else if (xd_done) begin xd_done_sticky<=1; xd_valid_sticky<=xd_valid; end
    end

    // --------------------------------------------------------
    // GIFT-COFB (0x5000_0000)
    // --------------------------------------------------------
    reg [127:0] gc_key, gc_nonce, gc_ad, gc_data_in, gc_tag_in;
    reg [  7:0] gc_ad_length, gc_data_length;
    reg         gc_decrypt_mode;
    reg         gc_start;
    reg         gc_ad_ack, gc_msg_ack;
    reg         gc_done_sticky, gc_valid_sticky;

    wire [127:0] gc_data_out, gc_tag_out;
    wire         gc_valid, gc_done;
    wire         gc_ad_req, gc_msg_req;
    wire         gc_data_out_valid;

    cofb_core u_giftcofb (
        .clk          (clk),           .rst_n        (resetn),
        .start        (gc_start),      .decrypt_mode (gc_decrypt_mode),
        .key          (gc_key),        .nonce        (gc_nonce),
        .ad_data      (gc_ad),         .ad_total_len (gc_ad_length),
        .ad_ack       (gc_ad_ack),
        .msg_data     (gc_data_in),    .msg_total_len(gc_data_length),
        .msg_ack      (gc_msg_ack),
        .tag_in       (gc_tag_in),
        .ad_req       (gc_ad_req),     .msg_req      (gc_msg_req),
        .data_out     (gc_data_out),   .data_out_valid(gc_data_out_valid),
        .tag_out      (gc_tag_out),
        .valid        (gc_valid),      .done         (gc_done)
    );

    always @(posedge clk) begin
        if      (!resetn)  begin gc_done_sticky<=0; gc_valid_sticky<=0; end
        else if (gc_start) begin gc_done_sticky<=0; gc_valid_sticky<=0; end
        else if (gc_done)  begin gc_done_sticky<=1; gc_valid_sticky<=gc_valid; end
    end

    // --------------------------------------------------------
    // PicoRV32 CPU
    // --------------------------------------------------------
    wire mem_valid, mem_instr;
    reg  mem_ready;
    wire [31:0] mem_addr,    mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    wire        mem_la_read,  mem_la_write;
    wire [31:0] mem_la_addr,  mem_la_wdata;
    wire [3:0]  mem_la_wstrb;

    picorv32 picorv32_core (
        .clk        (clk),          .resetn     (resetn),
        .trap       (trap),
        .mem_valid  (mem_valid),    .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),    .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),    .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata),
        .mem_la_read(mem_la_read),  .mem_la_write(mem_la_write),
        .mem_la_addr(mem_la_addr),  .mem_la_wdata(mem_la_wdata),
        .mem_la_wstrb(mem_la_wstrb)
    );

    // Boot BRAM  4 KB  — pre-loaded at synthesis, read-only
    reg [31:0] boot_mem [0:BOOT_SIZE-1];
    initial $readmemh("bootloader.hex", boot_mem);

    // App BRAM  64 KB  — written by bootloader at run-time
    reg [31:0] app_mem  [0:APP_SIZE-1];

    reg [31:0] m_read_data;
    reg        m_read_en;

    // ========================================================
    // FAST_MEMORY path  (FAST_MEMORY=1, default)
    //   mem_ready asserted every cycle; address decoded from
    //   mem_la_addr (look-ahead, 1 cycle ahead of mem_addr)
    // ========================================================
    generate
    if (FAST_MEMORY) begin : gen_fast_mem

        always @(posedge clk) begin
            if (!resetn) begin
                mem_ready       <= 0;
                out_byte_en     <= 0;
                uart_we         <= 0;   uart_rx_rd   <= 0;
                uart_div_we     <= 0;   uart_div_di  <= 0;
                tx_busy         <= 0;   tx_countdown <= 0;
                // TinyJAMBU
                jb_key<=0; jb_nonce<=0; jb_ad<=0; jb_data_in<=0; jb_tag_in<=0;
                jb_ad_length<=0; jb_data_length<=0; jb_sel_type<=3'b001; jb_ena<=0;
                // Xoodyak
                xd_key<=0; xd_nonce<=0; xd_ad<=0; xd_data_in<=0; xd_tag_in<=0;
                xd_ad_length<=0; xd_data_length<=0; xd_sel_type<=0; xd_ena<=0;
                // GIFT-COFB
                gc_key<=0; gc_nonce<=0; gc_ad<=0; gc_data_in<=0; gc_tag_in<=0;
                gc_ad_length<=0; gc_data_length<=0; gc_decrypt_mode<=0; gc_start<=0;
                gc_ad_ack<=0; gc_msg_ack<=0;
                // SD SPI
                sdspi_tx_data<=8'hFF; sdspi_clkdiv<=16'd199;
                sdspi_start<=0; sdspi_cs_n_reg<=1'b1;
            end else begin
                // defaults (single-cycle pulses)
                mem_ready     <= 1;
                out_byte_en   <= 0;
                uart_we       <= 0;
                uart_rx_rd    <= 0;
                uart_div_we   <= 0;
                uart_div_di   <= 0;
                jb_ena        <= 0;
                xd_ena        <= 0;
                gc_start      <= 0;
                gc_ad_ack     <= 0;
                gc_msg_ack    <= 0;
                sdspi_start   <= 0;

                // UART TX busy countdown
                if (tx_busy) begin
                    if (tx_countdown != 0) tx_countdown <= tx_countdown - 1;
                    else                   tx_busy      <= 0;
                end

                // ---- Default BRAM read (before peripheral override) ----
                if (mem_la_addr < 32'h0001_0000)
                    mem_rdata <= boot_mem[mem_la_addr >> 2];
                else if (mem_la_addr[31:16] == 16'h0001)
                    mem_rdata <= app_mem[(mem_la_addr - 32'h0001_0000) >> 2];
                else
                    mem_rdata <= 32'h0000_0000;

                // ---- Peripheral READ ----
                if (mem_la_read) begin
                    case (mem_la_addr)
                        // UART / GPIO
                        32'h1000_0008: begin mem_rdata <= uart_dat_do; uart_rx_rd <= 1; end
                        32'h1000_000C: mem_rdata <= {30'b0, uart_rx_valid, uart_tx_ready};
                        32'h1000_0010: mem_rdata <= uart_div_do;
                        32'h2000_0000: mem_rdata <= {28'b0, sw_sync2};
                        32'h2000_0004: mem_rdata <= {28'b0, btn_sync2};
                        // SD SPI
                        32'h6000_0000: mem_rdata <= {24'd0, sdspi_rx_data_reg};
                        32'h6000_0004: mem_rdata <= {29'd0, sdspi_cs_n_reg, sdspi_busy, sdspi_done_sticky};
                        32'h6000_0008: mem_rdata <= {31'd0, sdspi_cs_n_reg};
                        32'h6000_000C: mem_rdata <= {16'd0, sdspi_clkdiv};
                        // TinyJAMBU
                        32'h3000_0048: mem_rdata <= {30'd0, jb_done_sticky, jb_valid_sticky};
                        32'h3000_004C: mem_rdata <= jb_data_out[127: 96];
                        32'h3000_0050: mem_rdata <= jb_data_out[ 95: 64];
                        32'h3000_0054: mem_rdata <= jb_data_out[ 63: 32];
                        32'h3000_0058: mem_rdata <= jb_data_out[ 31:  0];
                        32'h3000_005C: mem_rdata <= jb_tag_out [ 63: 32];
                        32'h3000_0060: mem_rdata <= jb_tag_out [ 31:  0];
                        // Xoodyak
                        32'h4000_0054: mem_rdata <= {30'd0, xd_done_sticky, xd_valid_sticky};
                        32'h4000_0058: mem_rdata <= xd_data_out[127: 96];
                        32'h4000_005C: mem_rdata <= xd_data_out[ 95: 64];
                        32'h4000_0060: mem_rdata <= xd_data_out[ 63: 32];
                        32'h4000_0064: mem_rdata <= xd_data_out[ 31:  0];
                        32'h4000_0068: mem_rdata <= xd_tag_out [127: 96];
                        32'h4000_006C: mem_rdata <= xd_tag_out [ 95: 64];
                        32'h4000_0070: mem_rdata <= xd_tag_out [ 63: 32];
                        32'h4000_0074: mem_rdata <= xd_tag_out [ 31:  0];
                        // GIFT-COFB
                        32'h5000_0054: mem_rdata <= {28'd0, gc_ad_req, gc_msg_req, gc_done_sticky, gc_valid_sticky};
                        32'h5000_0058: mem_rdata <= gc_data_out[ 31:  0];
                        32'h5000_005C: mem_rdata <= gc_data_out[ 63: 32];
                        32'h5000_0060: mem_rdata <= gc_data_out[ 95: 64];
                        32'h5000_0064: mem_rdata <= gc_data_out[127: 96];
                        32'h5000_0068: mem_rdata <= gc_tag_out [ 31:  0];
                        32'h5000_006C: mem_rdata <= gc_tag_out [ 63: 32];
                        32'h5000_0070: mem_rdata <= gc_tag_out [ 95: 64];
                        32'h5000_0074: mem_rdata <= gc_tag_out [127: 96];
                        default: ;
                    endcase
                end

                // ---- WRITE ----
                if (mem_la_write) begin
                    // App BRAM (byte-enable)
                    if (mem_la_addr[31:16] == 16'h0001) begin
                        if (mem_la_wstrb[0]) app_mem[(mem_la_addr-32'h0001_0000)>>2][ 7: 0] <= mem_la_wdata[ 7: 0];
                        if (mem_la_wstrb[1]) app_mem[(mem_la_addr-32'h0001_0000)>>2][15: 8] <= mem_la_wdata[15: 8];
                        if (mem_la_wstrb[2]) app_mem[(mem_la_addr-32'h0001_0000)>>2][23:16] <= mem_la_wdata[23:16];
                        if (mem_la_wstrb[3]) app_mem[(mem_la_addr-32'h0001_0000)>>2][31:24] <= mem_la_wdata[31:24];
                    end else begin
                        case (mem_la_addr)
                            // LED
                            32'h1000_0000: begin out_byte_en<=1; out_byte<=mem_la_wdata[7:0]; end
                            // UART TX  (guard: not re-entrant while busy)
                            32'h1000_0004: begin
                                if (!tx_busy) begin
                                    uart_tx_data <= mem_la_wdata[7:0];
                                    uart_we      <= 1;
                                    tx_busy      <= 1;
                                    tx_countdown <= 16'd9000;
                                end
                            end
                            // UART baud divider
                            32'h1000_0010: begin uart_div_we<=mem_la_wstrb; uart_div_di<=mem_la_wdata; end
                            // SD SPI
                            32'h6000_0000: begin
                                if (!sdspi_busy) begin
                                    sdspi_tx_data <= mem_la_wdata[7:0];
                                    sdspi_start   <= 1'b1;
                                end
                            end
                            32'h6000_0008: sdspi_cs_n_reg <= mem_la_wdata[0];
                            32'h6000_000C: sdspi_clkdiv   <= mem_la_wdata[15:0];
                            // TinyJAMBU
                            32'h3000_0000: jb_key[ 127: 96] <= mem_la_wdata;
                            32'h3000_0004: jb_key[  95: 64] <= mem_la_wdata;
                            32'h3000_0008: jb_key[  63: 32] <= mem_la_wdata;
                            32'h3000_000C: jb_key[  31:  0] <= mem_la_wdata;
                            32'h3000_0010: jb_nonce[ 95: 64] <= mem_la_wdata;
                            32'h3000_0014: jb_nonce[ 63:32] <= mem_la_wdata;
                            32'h3000_0018: jb_nonce[ 31: 0] <= mem_la_wdata;
                            32'h3000_001C: jb_ad[  127: 96] <= mem_la_wdata;
                            32'h3000_0020: jb_ad[   95: 64] <= mem_la_wdata;
                            32'h3000_0024: jb_ad[   63: 32] <= mem_la_wdata;
                            32'h3000_0028: jb_ad[   31:  0] <= mem_la_wdata;
                            32'h3000_002C: jb_data_in[127:96] <= mem_la_wdata;
                            32'h3000_0030: jb_data_in[ 95:64] <= mem_la_wdata;
                            32'h3000_0034: jb_data_in[ 63:32] <= mem_la_wdata;
                            32'h3000_0038: jb_data_in[ 31:0] <= mem_la_wdata;
                            32'h3000_003C: jb_tag_in[ 63:32] <= mem_la_wdata;
                            32'h3000_0040: jb_tag_in[ 31: 0] <= mem_la_wdata;
                            32'h3000_0044: begin
                                jb_sel_type    <= mem_la_wdata[18:16];
                                jb_ad_length   <= mem_la_wdata[12: 8];
                                jb_data_length <= mem_la_wdata[ 4: 0];
                                jb_ena         <= 1'b1;
                            end
                            // Xoodyak
                            32'h4000_0000: xd_key[ 127: 96] <= mem_la_wdata;
                            32'h4000_0004: xd_key[  95: 64] <= mem_la_wdata;
                            32'h4000_0008: xd_key[  63: 32] <= mem_la_wdata;
                            32'h4000_000C: xd_key[  31:  0] <= mem_la_wdata;
                            32'h4000_0010: xd_nonce[127: 96] <= mem_la_wdata;
                            32'h4000_0014: xd_nonce[ 95: 64] <= mem_la_wdata;
                            32'h4000_0018: xd_nonce[ 63: 32] <= mem_la_wdata;
                            32'h4000_001C: xd_nonce[ 31:  0] <= mem_la_wdata;
                            32'h4000_0020: xd_ad[  127: 96] <= mem_la_wdata;
                            32'h4000_0024: xd_ad[   95: 64] <= mem_la_wdata;
                            32'h4000_0028: xd_ad[   63: 32] <= mem_la_wdata;
                            32'h4000_002C: xd_ad[   31:  0] <= mem_la_wdata;
                            32'h4000_0030: xd_data_in[127:96] <= mem_la_wdata;
                            32'h4000_0034: xd_data_in[ 95:64] <= mem_la_wdata;
                            32'h4000_0038: xd_data_in[ 63:32] <= mem_la_wdata;
                            32'h4000_003C: xd_data_in[ 31: 0] <= mem_la_wdata;
                            32'h4000_0040: xd_tag_in[ 127:96] <= mem_la_wdata;
                            32'h4000_0044: xd_tag_in[  95:64] <= mem_la_wdata;
                            32'h4000_0048: xd_tag_in[  63:32] <= mem_la_wdata;
                            32'h4000_004C: xd_tag_in[  31: 0] <= mem_la_wdata;
                            32'h4000_0050: begin
                                xd_sel_type    <= mem_la_wdata[18:16];
                                xd_ad_length   <= mem_la_wdata[12: 8];
                                xd_data_length <= mem_la_wdata[ 4: 0];
                                xd_ena         <= 1'b1;
                            end
                            // GIFT-COFB
                            32'h5000_0000: gc_key[  31:  0] <= mem_la_wdata;
                            32'h5000_0004: gc_key[  63: 32] <= mem_la_wdata;
                            32'h5000_0008: gc_key[  95: 64] <= mem_la_wdata;
                            32'h5000_000C: gc_key[ 127: 96] <= mem_la_wdata;
                            32'h5000_0010: gc_nonce[ 31: 0] <= mem_la_wdata;
                            32'h5000_0014: gc_nonce[ 63:32] <= mem_la_wdata;
                            32'h5000_0018: gc_nonce[ 95:64] <= mem_la_wdata;
                            32'h5000_001C: gc_nonce[127:96] <= mem_la_wdata;
                            32'h5000_0020: gc_ad[   31:  0] <= mem_la_wdata;
                            32'h5000_0024: gc_ad[   63: 32] <= mem_la_wdata;
                            32'h5000_0028: gc_ad[   95: 64] <= mem_la_wdata;
                            32'h5000_002C: gc_ad[  127: 96] <= mem_la_wdata;
                            32'h5000_0030: gc_data_in[ 31: 0] <= mem_la_wdata;
                            32'h5000_0034: gc_data_in[ 63:32] <= mem_la_wdata;
                            32'h5000_0038: gc_data_in[ 95:64] <= mem_la_wdata;
                            32'h5000_003C: gc_data_in[127:96] <= mem_la_wdata;
                            32'h5000_0040: gc_tag_in[ 31: 0] <= mem_la_wdata;
                            32'h5000_0044: gc_tag_in[ 63:32] <= mem_la_wdata;
                            32'h5000_0048: gc_tag_in[ 95:64] <= mem_la_wdata;
                            32'h5000_004C: gc_tag_in[127:96] <= mem_la_wdata;
                            32'h5000_0050: begin
                                gc_decrypt_mode <= mem_la_wdata[16];
                                gc_ad_length    <= mem_la_wdata[15:8];
                                gc_data_length  <= mem_la_wdata[ 7:0];
                                gc_start        <= 1'b1;
                            end
                            32'h5000_0078: begin
                                gc_ad_ack  <= mem_la_wdata[1];
                                gc_msg_ack <= mem_la_wdata[0];
                            end
                            default: ;
                        endcase
                    end
                end // mem_la_write
            end
        end // always

    // ========================================================
    // SLOW_MEMORY path  (FAST_MEMORY=0)
    //   Adds 1 wait-state; uses mem_addr (registered)
    // ========================================================
    end else begin : gen_slow_mem

        always @(posedge clk) begin
            if (!resetn) begin
                m_read_en<=0; mem_ready<=0; out_byte_en<=0;
                uart_we<=0; uart_rx_rd<=0; uart_div_we<=0; uart_div_di<=0;
                tx_busy<=0; tx_countdown<=0;
                jb_key<=0; jb_nonce<=0; jb_ad<=0; jb_data_in<=0; jb_tag_in<=0;
                jb_ad_length<=0; jb_data_length<=0; jb_sel_type<=3'b001; jb_ena<=0;
                xd_key<=0; xd_nonce<=0; xd_ad<=0; xd_data_in<=0; xd_tag_in<=0;
                xd_ad_length<=0; xd_data_length<=0; xd_sel_type<=0; xd_ena<=0;
                gc_key<=0; gc_nonce<=0; gc_ad<=0; gc_data_in<=0; gc_tag_in<=0;
                gc_ad_length<=0; gc_data_length<=0; gc_decrypt_mode<=0; gc_start<=0;
                gc_ad_ack<=0; gc_msg_ack<=0;
                sdspi_tx_data<=8'hFF; sdspi_clkdiv<=16'd199;
                sdspi_start<=0; sdspi_cs_n_reg<=1'b1;
            end else begin
                m_read_en   <= 0;
                mem_ready   <= mem_valid && !mem_ready && m_read_en;
                out_byte_en <= 0; uart_rx_rd<=0; uart_div_we<=0; uart_div_di<=0;
                jb_ena<=0; xd_ena<=0; gc_start<=0;
                gc_ad_ack<=0; gc_msg_ack<=0;
                sdspi_start<=0; uart_we<=0;

                if (tx_busy) begin
                    if (tx_countdown != 0) tx_countdown <= tx_countdown - 1;
                    else                   tx_busy      <= 0;
                end

                // Default BRAM read (registered, appears in mem_rdata next cycle)
                if (mem_addr < 32'h0001_0000)
                    m_read_data <= boot_mem[mem_addr >> 2];
                else if (mem_addr[31:16] == 16'h0001)
                    m_read_data <= app_mem[(mem_addr - 32'h0001_0000) >> 2];
                else
                    m_read_data <= 32'h0000_0000;
                mem_rdata <= m_read_data;
            end

            (* parallel_case *)
            case (1)
                // --- BRAM reads ---
                mem_valid && !mem_ready && !mem_wstrb && (mem_addr < 32'h0002_0000):
                    m_read_en <= 1;
                // --- Peripheral reads ---
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h1000_0008:
                    begin mem_rdata<=uart_dat_do; uart_rx_rd<=1; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h1000_000C:
                    begin mem_rdata<={30'b0,uart_rx_valid,uart_tx_ready}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h1000_0010:
                    begin mem_rdata<=uart_div_do; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h2000_0000:
                    begin mem_rdata<={28'b0,sw_sync2}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h2000_0004:
                    begin mem_rdata<={28'b0,btn_sync2}; mem_ready<=1; end
                // SD SPI reads
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h6000_0000:
                    begin mem_rdata<={24'd0,sdspi_rx_data_reg}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h6000_0004:
                    begin mem_rdata<={29'd0,sdspi_cs_n_reg,sdspi_busy,sdspi_done_sticky}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h6000_0008:
                    begin mem_rdata<={31'd0,sdspi_cs_n_reg}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h6000_000C:
                    begin mem_rdata<={16'd0,sdspi_clkdiv}; mem_ready<=1; end
                // TinyJAMBU reads
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_0048:
                    begin mem_rdata<={30'd0,jb_done_sticky,jb_valid_sticky}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_004C:
                    begin mem_rdata<=jb_data_out[127: 96]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_0050:
                    begin mem_rdata<=jb_data_out[ 95: 64]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_0054:
                    begin mem_rdata<=jb_data_out[ 63: 32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_0058:
                    begin mem_rdata<=jb_data_out[ 31:  0]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_005C:
                    begin mem_rdata<=jb_tag_out [ 63: 32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h3000_0060:
                    begin mem_rdata<=jb_tag_out [ 31:  0]; mem_ready<=1; end
                // Xoodyak reads
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0054:
                    begin mem_rdata<={30'd0,xd_done_sticky,xd_valid_sticky}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0058:
                    begin mem_rdata<=xd_data_out[127: 96]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_005C:
                    begin mem_rdata<=xd_data_out[ 95: 64]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0060:
                    begin mem_rdata<=xd_data_out[ 63: 32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0064:
                    begin mem_rdata<=xd_data_out[ 31:  0]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0068:
                    begin mem_rdata<=xd_tag_out [127: 96]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_006C:
                    begin mem_rdata<=xd_tag_out [ 95: 64]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0070:
                    begin mem_rdata<=xd_tag_out [ 63: 32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h4000_0074:
                    begin mem_rdata<=xd_tag_out [ 31:  0]; mem_ready<=1; end
                // GIFT-COFB reads
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0054:
                    begin mem_rdata<={28'd0,gc_ad_req,gc_msg_req,gc_done_sticky,gc_valid_sticky}; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0058:
                    begin mem_rdata<=gc_data_out[ 31: 0]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_005C:
                    begin mem_rdata<=gc_data_out[ 63:32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0060:
                    begin mem_rdata<=gc_data_out[ 95:64]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0064:
                    begin mem_rdata<=gc_data_out[127:96]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0068:
                    begin mem_rdata<=gc_tag_out[ 31: 0]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_006C:
                    begin mem_rdata<=gc_tag_out[ 63:32]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0070:
                    begin mem_rdata<=gc_tag_out[ 95:64]; mem_ready<=1; end
                mem_valid && !mem_ready && !mem_wstrb && mem_addr==32'h5000_0074:
                    begin mem_rdata<=gc_tag_out[127:96]; mem_ready<=1; end
                // --- WRITES ---
                // App BRAM
                mem_valid && !mem_ready && |mem_wstrb && mem_addr[31:16]==16'h0001: begin
                    if (mem_wstrb[0]) app_mem[(mem_addr-32'h0001_0000)>>2][ 7: 0]<=mem_wdata[ 7: 0];
                    if (mem_wstrb[1]) app_mem[(mem_addr-32'h0001_0000)>>2][15: 8]<=mem_wdata[15: 8];
                    if (mem_wstrb[2]) app_mem[(mem_addr-32'h0001_0000)>>2][23:16]<=mem_wdata[23:16];
                    if (mem_wstrb[3]) app_mem[(mem_addr-32'h0001_0000)>>2][31:24]<=mem_wdata[31:24];
                    mem_ready<=1;
                end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h1000_0000:
                    begin out_byte_en<=1; out_byte<=mem_wdata[7:0]; mem_ready<=1; end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h1000_0004: begin
                    if (!tx_busy) begin
                        uart_tx_data<=mem_wdata[7:0]; uart_we<=1;
                        tx_busy<=1; tx_countdown<=16'd10500;
                    end
                    mem_ready<=1;
                end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h1000_0010:
                    begin uart_div_we<=mem_wstrb; uart_div_di<=mem_wdata; mem_ready<=1; end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h6000_0000: begin
                    if (!sdspi_busy) begin sdspi_tx_data<=mem_wdata[7:0]; sdspi_start<=1; end
                    mem_ready<=1;
                end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h6000_0008:
                    begin sdspi_cs_n_reg<=mem_wdata[0]; mem_ready<=1; end
                mem_valid && !mem_ready && |mem_wstrb && mem_addr==32'h6000_000C:
                    begin sdspi_clkdiv<=mem_wdata[15:0]; mem_ready<=1; end
                // TinyJAMBU writes
                mem_valid && !mem_ready && |mem_wstrb && mem_addr[31:8]==24'h30_0000: begin
                    case (mem_addr[7:0])
                        8'h00: jb_key[127: 96]<=mem_wdata; 8'h04: jb_key[ 95: 64]<=mem_wdata;
                        8'h08: jb_key[ 63: 32]<=mem_wdata; 8'h0C: jb_key[ 31:  0]<=mem_wdata;
                        8'h10: jb_nonce[ 95: 64]<=mem_wdata; 8'h14: jb_nonce[ 63: 32]<=mem_wdata;
                        8'h18: jb_nonce[ 31: 0]<=mem_wdata;
                        8'h1C: jb_ad[127: 96]<=mem_wdata;  8'h20: jb_ad[ 95: 64]<=mem_wdata;
                        8'h24: jb_ad[ 63: 32]<=mem_wdata;  8'h28: jb_ad[ 31:  0]<=mem_wdata;
                        8'h2C: jb_data_in[127:96]<=mem_wdata; 8'h30: jb_data_in[ 95:64]<=mem_wdata;
                        8'h34: jb_data_in[ 63:32]<=mem_wdata; 8'h38: jb_data_in[ 31: 0]<=mem_wdata;
                        8'h3C: jb_tag_in[ 63:32]<=mem_wdata;  8'h40: jb_tag_in[ 31: 0]<=mem_wdata;
                        8'h44: begin
                            jb_sel_type<=mem_wdata[18:16]; jb_ad_length<=mem_wdata[12:8];
                            jb_data_length<=mem_wdata[4:0]; jb_ena<=1;
                        end
                    endcase
                    mem_ready<=1;
                end
                // Xoodyak writes
                mem_valid && !mem_ready && |mem_wstrb && mem_addr[31:8]==24'h40_0000: begin
                    case (mem_addr[7:0])
                        8'h00: xd_key[127: 96]<=mem_wdata; 8'h04: xd_key[ 95: 64]<=mem_wdata;
                        8'h08: xd_key[ 63: 32]<=mem_wdata; 8'h0C: xd_key[ 31:  0]<=mem_wdata;
                        8'h10: xd_nonce[127: 96]<=mem_wdata; 8'h14: xd_nonce[ 95: 64]<=mem_wdata;
                        8'h18: xd_nonce[ 63: 32]<=mem_wdata; 8'h1C: xd_nonce[ 31:  0]<=mem_wdata;
                        8'h20: xd_ad[127: 96]<=mem_wdata;  8'h24: xd_ad[ 95: 64]<=mem_wdata;
                        8'h28: xd_ad[ 63: 32]<=mem_wdata;  8'h2C: xd_ad[ 31:  0]<=mem_wdata;
                        8'h30: xd_data_in[127:96]<=mem_wdata; 8'h34: xd_data_in[ 95:64]<=mem_wdata;
                        8'h38: xd_data_in[ 63:32]<=mem_wdata; 8'h3C: xd_data_in[ 31: 0]<=mem_wdata;
                        8'h40: xd_tag_in[127:96]<=mem_wdata;  8'h44: xd_tag_in[ 95:64]<=mem_wdata;
                        8'h48: xd_tag_in[ 63:32]<=mem_wdata;  8'h4C: xd_tag_in[ 31: 0]<=mem_wdata;
                        8'h50: begin
                            xd_sel_type<=mem_wdata[18:16]; xd_ad_length<=mem_wdata[12:8];
                            xd_data_length<=mem_wdata[4:0]; xd_ena<=1;
                        end
                    endcase
                    mem_ready<=1;
                end
                // GIFT-COFB writes
                mem_valid && !mem_ready && |mem_wstrb && mem_addr[31:8]==24'h50_0000: begin
                    case (mem_addr[7:0])
                        8'h00: gc_key[ 31: 0]<=mem_wdata;  8'h04: gc_key[ 63:32]<=mem_wdata;
                        8'h08: gc_key[ 95:64]<=mem_wdata;  8'h0C: gc_key[127:96]<=mem_wdata;
                        8'h10: gc_nonce[ 31: 0]<=mem_wdata; 8'h14: gc_nonce[ 63:32]<=mem_wdata;
                        8'h18: gc_nonce[ 95:64]<=mem_wdata; 8'h1C: gc_nonce[127:96]<=mem_wdata;
                        8'h20: gc_ad[ 31: 0]<=mem_wdata;   8'h24: gc_ad[ 63:32]<=mem_wdata;
                        8'h28: gc_ad[ 95:64]<=mem_wdata;   8'h2C: gc_ad[127:96]<=mem_wdata;
                        8'h30: gc_data_in[ 31: 0]<=mem_wdata; 8'h34: gc_data_in[ 63:32]<=mem_wdata;
                        8'h38: gc_data_in[ 95:64]<=mem_wdata; 8'h3C: gc_data_in[127:96]<=mem_wdata;
                        8'h40: gc_tag_in[ 31: 0]<=mem_wdata;  8'h44: gc_tag_in[ 63:32]<=mem_wdata;
                        8'h48: gc_tag_in[ 95:64]<=mem_wdata;  8'h4C: gc_tag_in[127:96]<=mem_wdata;
                        8'h50: begin
                            gc_decrypt_mode<=mem_wdata[16]; gc_ad_length<=mem_wdata[15:8];
                            gc_data_length<=mem_wdata[7:0]; gc_start<=1;
                        end
                        8'h78: begin gc_ad_ack<=mem_wdata[1]; gc_msg_ack<=mem_wdata[0]; end
                    endcase
                    mem_ready<=1;
                end

                default: ;
            endcase
        end // always

    end
    endgenerate

endmodule
