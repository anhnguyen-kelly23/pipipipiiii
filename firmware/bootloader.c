/*
 * bootloader.c — PicoRV32 SD-card bootloader
 *
 * Memory map:
 *   Boot BRAM : 0x0000_0000 – 0x0000_0FFF  (4 KB, read-only code+rodata)
 *   App  BRAM : 0x0001_0000 – 0x0001_FFFF  (64 KB)
 *     FW area : 0x0001_0000 – 0x0001_EFFF  (60 KB, loaded from SD)
 *     BL data : 0x0001_F000 – 0x0001_FFFF  (4 KB, bootloader .bss + stack)
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
#define MAX_FW_BYTES     (60UL * 1024UL)   /* 60 KB — chừa 4 KB cho BL data */

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
 *
 * Dùng done_sticky (bit 0) thay vì busy (bit 1) để tránh
 * race condition ở tốc độ SPI cao.
 * ========================================================= */
static uint8_t spi_xfer(uint8_t tx)
{
    while (SD_STATUS & 0x2);          /* wait: not busy              */
    SD_DATA = tx;                     /* start xfer, clears done_sticky */
    while (!(SD_STATUS & 0x1));       /* wait: done_sticky = 1       */
    return (uint8_t)(SD_DATA & 0xFF); /* rx_data valid after done    */
}

static inline uint8_t sd_dummy(void) { return spi_xfer(0xFF); }
static inline void    cs_lo(void)    { SD_CS = 0; }
static inline void    cs_hi(void)    { SD_CS = 1; }

static void sd_end(void) { sd_dummy(); cs_hi(); }

/* =========================================================
 * sd_cmd — gửi 6-byte command, chờ R1 (bit7=0)
 * ========================================================= */
static uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    uint8_t r;
    unsigned int n;

    cs_lo();
    sd_dummy();
    spi_xfer(cmd);
    spi_xfer((arg >> 24) & 0xFF);
    spi_xfer((arg >> 16) & 0xFF);
    spi_xfer((arg >>  8) & 0xFF);
    spi_xfer((arg      ) & 0xFF);
    spi_xfer(crc);

    for (n = 1000; n; n--) {
        r = sd_dummy();
        if (!(r & 0x80)) return r;
    }
    uart_puts("  [WARN] sd_cmd timeout\r\n");
    return 0xFF;
}

/* =========================================================
 * sd_poweron — >= 80 clock pulses với CS=HIGH
 * ========================================================= */
static void sd_poweron(void)
{
    SD_CLKDIV = 199;
    cs_hi();
    for (int i = 0; i < 20; i++)
        sd_dummy();
}

/* CMD0 */
static int sd_cmd0(void)
{
    uart_puts("  CMD0  ... ");
    uint8_t r = sd_cmd(0x40, 0, 0x95);
    sd_end();
    if (r != 0x01) { uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n"); return -1; }
    uart_puts("OK\r\n");
    return 0;
}

/* CMD8 */
static int sd_cmd8(void)
{
    uart_puts("  CMD8  ... ");
    uint8_t r = sd_cmd(0x48, 0x000001AA, 0x87);
    if (r != 0x01) {
        sd_end();
        uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n");
        return -1;
    }
    sd_dummy();
    sd_dummy();
    uint8_t volt = sd_dummy() & 0xF;
    uint8_t echo = sd_dummy();
    sd_end();
    if (volt != 0x1 || echo != 0xAA) {
        uart_puts("FAIL\r\n");
        return -1;
    }
    uart_puts("OK\r\n");
    return 0;
}

/* ACMD41 */
static int sd_acmd41(void)
{
    uint8_t r;
    uart_puts("  ACMD41... ");
    do {
        sd_cmd(0x77, 0, 0x65);
        sd_end();
        r = sd_cmd(0x69, 0x40000000, 0x77);
        sd_end();
    } while (r == 0x01);
    if (r != 0x00) {
        uart_puts("FAIL R1=0x"); uart_puth(r); uart_puts("\r\n");
        return -1;
    }
    uart_puts("OK\r\n");
    return 0;
}

/* CMD58 — READ_OCR */
static int g_sdhc = 0;

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
    uint8_t ocr0 = sd_dummy();
    sd_dummy(); sd_dummy(); sd_dummy();
    sd_end();
    if (!(ocr0 & 0x80)) {
        uart_puts("FAIL\r\n");
        return -1;
    }
    g_sdhc = (ocr0 & 0x40) ? 1 : 0;
    uart_puts("OCR=0x"); uart_puth(ocr0);
    uart_puts(g_sdhc ? " SDHC\r\n" : " SDSC\r\n");
    return 0;
}

/* CMD16 — SET_BLOCKLEN */
static void sd_cmd16(void)
{
    uart_puts("  CMD16 ... ");
    uint8_t r = sd_cmd(0x50, 0x200, 0x15);
    sd_end();
    uart_puts("R1=0x"); uart_puth(r);
    uart_puts(r == 0x00 ? " OK\r\n" : " (ignored)\r\n");
}

/* sd_init */
static int sd_init(void)
{
    sd_poweron();
    if (sd_cmd0()   != 0) return -1;
    if (sd_cmd8()   != 0) return -2;
    if (sd_acmd41() != 0) return -3;
    if (sd_cmd58()  != 0) return -4;
    sd_cmd16();
    SD_CLKDIV = 3;                   /* ~12.5 MHz (safe)   */
    uart_puts("  SPI 12.5MHz\r\n");
    return 0;
}

/* =========================================================
 * sd_read_sector — đọc 512-byte sector từ SD card
 * ========================================================= */
static int sd_read_sector(uint32_t sector, uint8_t *buf)
{
    uint32_t arg = g_sdhc ? sector : (sector * 512);
    uint8_t r;
    int timeout;

    r = sd_cmd(0x51, arg, 0x01);
    if (r != 0x00) {
        cs_hi();
        sd_dummy();
        return -1;
    }

    timeout = 100000;
    do {
        r = spi_xfer(0xFF);
        if (--timeout == 0) {
            cs_hi();
            sd_dummy();
            return -2;
        }
    } while (r != 0xFE);

    for (int i = 0; i < 512; i++)
        buf[i] = spi_xfer(0xFF);

    spi_xfer(0xFF);  /* CRC byte 1 */
    spi_xfer(0xFF);  /* CRC byte 2 */

    cs_hi();
    sd_dummy();

    return 0;
}

/* =========================================================
 * load_fw — đọc header, load toàn bộ firmware vào App BRAM
 *
 * sbuf[512] nằm ở BL_RAM (0x1F000+) nhờ linker script,
 * KHÔNG xung đột với firmware load area (0x10000+).
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

