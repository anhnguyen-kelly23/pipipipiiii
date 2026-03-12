/*
 * bootloader.c — PicoRV32 SD-card bootloader
 *
 * Memory map:
 *   Boot BRAM : 0x0000_0000 – 0x0000_0FFF  (4 KB, read-only)
 *   App  BRAM : 0x0001_0000 – 0x0001_FFFF  (64 KB, loaded from SD)
 *
 * SD card layout (sector 2048 = 1 MB offset):
 *   byte [0..3]  firmware size, little-endian uint32
 *   byte [4..]   firmware binary
 *
 * LED status:
 *   0x01  boot started
 *   0x03  SD init OK
 *   0x07  firmware loaded OK  → jump
 *   0xFF  SD init failed
 *   0xFE  firmware load failed
 */

#include <stdint.h>

/* =========================================================
 * MMIO registers
 * ========================================================= */
#define LED         (*(volatile uint32_t *)0x10000000)
#define UART_TX     (*(volatile uint32_t *)0x10000004)
#define UART_STATUS (*(volatile uint32_t *)0x1000000C)
/* UART_STATUS[0] = tx_ready (!tx_busy) */

#define SD_DATA     (*(volatile uint32_t *)0x60000000) /* W=tx  R=rx      */
#define SD_STATUS   (*(volatile uint32_t *)0x60000004) /* [1]=busy [0]=done */
#define SD_CS       (*(volatile uint32_t *)0x60000008) /* [0]=cs_n          */
#define SD_CLKDIV   (*(volatile uint32_t *)0x6000000C) /* half-period divider */

#define APP_BASE         0x00010000UL
#define APP_START_SECTOR 2048UL
#define MAX_FW_BYTES     (63UL * 1024UL)

/* =========================================================
 * memcpy (no stdlib)
 * ========================================================= */
void *memcpy(void *dst, const void *src, unsigned int n)
{
    uint8_t       *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    while (n--) *d++ = *s++;
    return dst;
}

/* =========================================================
 * UART helpers
 * ========================================================= */
static void uart_putc(char c)
{
    while (!(UART_STATUS & 1));  /* chờ tx_ready */
    UART_TX = (uint8_t)c;
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static void uart_puth(uint8_t v)          /* print 2 hex digits */
{
    const char hex[] = "0123456789ABCDEF";
    uart_putc(hex[v >> 4]);
    uart_putc(hex[v & 0xF]);
}

static void uart_puthw(uint32_t v)        /* print 8 hex digits */
{
    uart_puth((v >> 24) & 0xFF);
    uart_puth((v >> 16) & 0xFF);
    uart_puth((v >>  8) & 0xFF);
    uart_puth((v      ) & 0xFF);
}

/* =========================================================
 * SPI low-level
 *   SD_STATUS[1] = busy  (transfer in progress)
 *   SD_STATUS[0] = done  (sticky, cleared on next start)
 * ========================================================= */
static uint8_t spi_xfer(uint8_t tx)
{
    while (SD_STATUS & 0x2);         /* wait: not busy     */
    SD_DATA = tx;                    /* start transfer     */
    while (!(SD_STATUS & 0x1));      /* wait: done         */
    return (uint8_t)(SD_DATA & 0xFF);
}

static inline uint8_t sd_dummy(void) { return spi_xfer(0xFF); }
static inline void    cs_lo(void)    { SD_CS = 0; }  /* assert   CS */
static inline void    cs_hi(void)    { SD_CS = 1; }  /* deassert CS */

/* 1 dummy byte + deassert CS — chuẩn kết thúc lệnh */
static void sd_end(void) { sd_dummy(); cs_hi(); }

/* =========================================================
 * sd_cmd — gửi 6-byte command, chờ R1 (bit7=0)
 *   Trả về byte R1; caller giữ CS sau đó.
 * ========================================================= */
static uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    uint8_t r;
    unsigned int n;

    cs_lo();
    sd_dummy();                      /* 1 byte padding     */
    spi_xfer(cmd);
    spi_xfer((arg >> 24) & 0xFF);
    spi_xfer((arg >> 16) & 0xFF);
    spi_xfer((arg >>  8) & 0xFF);
    spi_xfer((arg      ) & 0xFF);
    spi_xfer(crc);

    /* poll R1: bỏ 0xFF đầu, tối đa 1000 lần */
    for (n = 1000; n; n--) {
        r = sd_dummy();
        if (!(r & 0x80)) return r;
    }
    uart_puts("  [WARN] sd_cmd timeout\r\n");
    return 0xFF;
}

/* =========================================================
 * sd_poweron — >= 80 clock pulses với CS=HIGH (SPI entry)
 * ========================================================= */
static void sd_poweron(void)
{
    SD_CLKDIV = 199;                 /* ~250 kHz           */
    cs_hi();
    for (int i = 0; i < 20; i++)    /* 20*8=160 clocks    */
        sd_dummy();
}

/* =========================================================
 * CMD0 — GO_IDLE_STATE → R1 phải = 0x01
 * ========================================================= */
static int sd_cmd0(void)
{
    uart_puts("  CMD0  ... ");
    uint8_t r = sd_cmd(0x40, 0, 0x95);
    sd_end();
    if (r != 0x01) { uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n"); return -1; }
    uart_puts("OK\r\n");
    return 0;
}

/* =========================================================
 * CMD8 — SEND_IF_COND → xác nhận SD v2 + 3.3V
 *   R1=0x01, voltage nibble=0x1, echo=0xAA
 * ========================================================= */
static int sd_cmd8(void)
{
    uart_puts("  CMD8  ... ");
    uint8_t r = sd_cmd(0x48, 0x000001AA, 0x87);
    if (r != 0x01) {
        sd_end();
        uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n");
        return -1;
    }
    sd_dummy();                      /* cmd version (bỏ)   */
    sd_dummy();                      /* reserved    (bỏ)   */
    uint8_t volt = sd_dummy() & 0xF; /* voltage nibble     */
    uint8_t echo = sd_dummy();       /* echo pattern       */
    sd_end();
    if (volt != 0x1 || echo != 0xAA) {
        uart_puts("FAIL volt=0x"); uart_puth(volt);
        uart_puts(" echo=0x");    uart_puth(echo);
        uart_puts("\r\n");
        return -1;
    }
    uart_puts("OK\r\n");
    return 0;
}

/* =========================================================
 * ACMD41 — SD_SEND_OP_COND, HCS=1
 *   CMD55 → ACMD41, lặp cho đến R1=0x00
 * ========================================================= */
static int sd_acmd41(void)
{
    uint8_t r;
    uart_puts("  ACMD41... ");
    do {
        sd_cmd(0x77, 0, 0x65);       /* CMD55 */
        sd_end();
        r = sd_cmd(0x69, 0x40000000, 0x77); /* ACMD41 HCS=1 */
        sd_end();
    } while (r == 0x01);             /* 0x01 = still initializing */
    if (r != 0x00) {
        uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n");
        return -1;
    }
    uart_puts("OK\r\n");
    return 0;
}

/* =========================================================
 * CMD58 — READ_OCR
 *   Kiểm tra Power-Up Status (bit7) và lấy CCS (bit6)
 *   QUAN TRỌNG: set g_sdhc tại đây để CMD17 dùng đúng địa chỉ
 * ========================================================= */
static int g_sdhc = 0;  /* 1=SDHC/SDXC (sector addr), 0=SDSC (byte addr) */

static int sd_cmd58(void)
{
    uart_puts("  CMD58 ... ");
    uint8_t r = sd_cmd(0x7A, 0, 0xFD);
    if (r != 0x00) {
        sd_dummy(); sd_dummy(); sd_dummy(); sd_dummy();
        sd_end();
        uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n");
        return -1;
    }
    uint8_t ocr0 = sd_dummy();       /* [7]=PwrUp [6]=CCS  */
    sd_dummy(); sd_dummy(); sd_dummy();
    sd_end();
    if (!(ocr0 & 0x80)) {
        uart_puts("FAIL PowerUp=0 OCR=0x"); uart_puth(ocr0); uart_puts("\r\n");
        return -1;
    }
    g_sdhc = (ocr0 & 0x40) ? 1 : 0; /* *** set g_sdhc *** */
    uart_puts("OCR=0x"); uart_puth(ocr0);
    uart_puts(g_sdhc ? " SDHC\r\n" : " SDSC\r\n");
    return 0;
}

/* =========================================================
 * CMD16 — SET_BLOCKLEN = 512 bytes
 *   Chỉ cần cho SDSC; SDHC/SDXC từ chối nhưng vẫn dùng 512.
 *   KHÔNG return lỗi — gọi xong bỏ qua.
 * ========================================================= */
static void sd_cmd16(void)
{
    uart_puts("  CMD16 ... ");
    uint8_t r = sd_cmd(0x50, 0x200, 0x15);
    sd_end();
    uart_puts("R1=0x"); uart_puth(r);
    uart_puts(r == 0x00 ? " OK\r\n" : " (ignored)\r\n");
}

/* =========================================================
 * sd_init — full init sequence
 * ========================================================= */
static int sd_init(void)
{
    sd_poweron();
    if (sd_cmd0()   != 0) return -1;
    if (sd_cmd8()   != 0) return -2;
    if (sd_acmd41() != 0) return -3;
    if (sd_cmd58()  != 0) return -4;
    sd_cmd16();                      /* KHÔNG check lỗi    */
    SD_CLKDIV = 1;                   /* 25 MHz full speed  */
    uart_puts("  SPI 25MHz\r\n");
    return 0;
}

/* =========================================================
 * CMD17 — READ_SINGLE_BLOCK (512 bytes)
 *   SDHC : arg = sector number
 *   SDSC : arg = byte address = sector * 512
 * ========================================================= */
/* =========================================================
 * Đọc một sector 512-byte từ thẻ SD vào buf[]
 * Đã sửa lỗi giữ tín hiệu CS liên tục cho đến khi nhận đủ Data Token
 * ========================================================= */
static int sd_read_sector(uint32_t sector, uint8_t *buf)
{
    uint32_t arg = g_sdhc ? sector : (sector * 512);
    uint8_t r;
    int timeout;

    // sd_cmd() đã gọi cs_lo() bên trong, không cần cs_assert()
    r = sd_cmd(0x51, arg, 0x01);   // ← 0x51 = CMD17
    if (r != 0x00) {
        cs_hi();                    // ← cs_hi() đúng tên
        sd_dummy();
        return -1;
    }

    timeout = 100000;
    do {
        r = spi_xfer(0xFF);
        if (--timeout == 0) {
            cs_hi();                // ← cs_hi()
            sd_dummy();
            return -2;
        }
    } while (r != 0xFE);

    for (int i = 0; i < 512; i++)
        buf[i] = spi_xfer(0xFF);

    spi_xfer(0xFF);  // CRC byte 1
    spi_xfer(0xFF);  // CRC byte 2

    cs_hi();         // ← cs_hi()
    sd_dummy();      // 8 extra clocks

    return 0;
}
/* =========================================================
 * load_fw — đọc header, load toàn bộ firmware vào App BRAM
 * ========================================================= */
static uint8_t sbuf[512];

static int load_fw(void)
{
    uint8_t  *app    = (uint8_t *)APP_BASE;
    uint32_t  sector = APP_START_SECTOR;

    /* Header sector */
    uart_puts("  Sector 0x"); uart_puthw(sector); uart_puts("... ");
    if (sd_read_sector(sector++, sbuf) != 0) return -1;
    uart_puts("OK\r\n");

    /* byte [0..3]: firmware size */
    uint32_t sz = (uint32_t)sbuf[0]
                | ((uint32_t)sbuf[1] <<  8)
                | ((uint32_t)sbuf[2] << 16)
                | ((uint32_t)sbuf[3] << 24);
    uart_puts("  FW size=0x"); uart_puthw(sz); uart_puts("\r\n");

    if (sz == 0 || sz > MAX_FW_BYTES) {
        uart_puts("  Bad size!\r\n");
        return -2;
    }

    /* byte [4..511]: đầu firmware (508 bytes tối đa) */
    uint32_t written = (sz < 508) ? sz : 508;
    memcpy(app, sbuf + 4, written);

    /* Các sector tiếp theo */
    while (written < sz) {
        if (sd_read_sector(sector++, sbuf) != 0) return -3;
        uint32_t chunk = sz - written;
        if (chunk > 512) chunk = 512;
        memcpy(app + written, sbuf, chunk);
        written += chunk;
    }

    uart_puts("  Loaded 0x"); uart_puthw(written); uart_puts(" bytes OK\r\n");
    return 0;
}

/* =========================================================
 * Entry point
 * ========================================================= */
void bootloader_main(void)
{
    LED = 0x01;
    uart_puts("\r\n====================\r\n");
    uart_puts("[BOOT] SD Bootloader\r\n");
    uart_puts("====================\r\n");

    /* --- SD init --- */
    uart_puts("[1] SD Init\r\n");
    if (sd_init() != 0) {
        uart_puts("[FAIL] SD Init\r\n");
        LED = 0xFF;
        while (1);
    }
    uart_puts("[1] SD Init OK\r\n");
    LED = 0x03;

    /* --- Load firmware --- */
    uart_puts("[2] Load FW\r\n");
    if (load_fw() != 0) {
        uart_puts("[FAIL] Load FW\r\n");
        LED = 0xFE;
        while (1);
    }
    uart_puts("[2] Load FW OK\r\n");
    LED = 0x07;

    /* --- Jump --- */
    uart_puts("[3] Jump 0x00010000\r\n");
    for (volatile int i = 0; i < 10000; i++);

    ((void (*)(void))APP_BASE)();
    while (1);
}
