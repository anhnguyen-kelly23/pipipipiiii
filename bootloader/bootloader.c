//============================================================================
// SD Card Bootloader for PicoRV32
// 
// Chức năng:
//   - Chờ SD card init xong (hardware sd_controller tự động làm)
//   - Đọc firmware từ SD card (raw sectors) vào RAM
//   - Jump đến firmware
//
// Yêu cầu:
//   - sd_cpu_interface.v phải được tích hợp vào system.v
//   - Firmware binary được ghi vào SD card từ sector SD_BASE_SECTOR
//============================================================================

#include <stdint.h>

//----------------------------------------------------------------------------
// Memory-mapped registers
//----------------------------------------------------------------------------

// SD CPU Interface registers (base: 0x7000_0000)
#define SD_STATUS      (*(volatile uint32_t*)0x70000000)
#define SD_BLOCK_ADDR  (*(volatile uint32_t*)0x70000004)
#define SD_CONTROL     (*(volatile uint32_t*)0x70000008)
#define SD_DATA        (*(volatile uint32_t*)0x7000000C)
#define SD_BYTE_COUNT  (*(volatile uint32_t*)0x70000010)

// Status bits
#define SD_STATUS_INIT_DONE    (1 << 0)
#define SD_STATUS_BLOCK_DONE   (1 << 1)
#define SD_STATUS_DATA_VALID   (1 << 2)
#define SD_STATUS_FIFO_EMPTY   (1 << 3)

// Control bits
#define SD_CTRL_START_READ     (1 << 0)

// LEDs for debug (tùy board)
#define REG_LEDS       (*(volatile uint32_t*)0x03000000)

//----------------------------------------------------------------------------
// Cấu hình bootloader
//----------------------------------------------------------------------------

// Địa chỉ RAM để load firmware
#define FW_BASE_ADDR       0x00002000

// Sector bắt đầu của firmware trên SD card
#define SD_BASE_SECTOR     100

// Số sectors cần đọc (mỗi sector = 512 bytes)
// 32 sectors = 16KB firmware
#define FW_SECTORS         32

// Bytes per sector
#define SECTOR_SIZE        512

//----------------------------------------------------------------------------
// Hàm hỗ trợ
//----------------------------------------------------------------------------

static inline void led_set(uint8_t value) {
    REG_LEDS = value;
}

// Chờ SD card init xong
static void wait_sd_init(void) {
    while (!(SD_STATUS & SD_STATUS_INIT_DONE)) {
        // Chờ hardware sd_controller hoàn thành init
    }
}

// Đọc 1 block (512 bytes) từ SD card vào buffer
static void sd_read_block(uint32_t sector, uint8_t *buffer) {
    // Set địa chỉ sector
    SD_BLOCK_ADDR = sector;
    
    // Trigger đọc
    SD_CONTROL = SD_CTRL_START_READ;
    
    // Chờ block done
    while (!(SD_STATUS & SD_STATUS_BLOCK_DONE)) {
        // Chờ
    }
    
    // Đọc 512 bytes từ FIFO
    for (int i = 0; i < SECTOR_SIZE; i++) {
        buffer[i] = (uint8_t)SD_DATA;
    }
}

// Đọc nhiều blocks liên tiếp
static void sd_read_blocks(uint32_t start_sector, uint8_t *buffer, uint32_t num_sectors) {
    for (uint32_t i = 0; i < num_sectors; i++) {
        sd_read_block(start_sector + i, buffer + (i * SECTOR_SIZE));
    }
}

//----------------------------------------------------------------------------
// Jump to firmware
//----------------------------------------------------------------------------

typedef void (*fw_entry_t)(void);

static void __attribute__((noreturn)) jump_to_firmware(uint32_t addr) {
    // Flush any pending operations
    asm volatile("fence.i");
    
    // Jump!
    fw_entry_t entry = (fw_entry_t)addr;
    entry();
    
    // Never returns
    while(1);
}

//----------------------------------------------------------------------------
// Main bootloader
//----------------------------------------------------------------------------

void __attribute__((noreturn)) bootloader_main(void) {
    
    // LED pattern: đang boot
    led_set(0x01);
    
    // 1. Chờ SD card init
    wait_sd_init();
    led_set(0x03);
    
    // 2. Đọc firmware từ SD card vào RAM
    uint8_t *fw_ptr = (uint8_t*)FW_BASE_ADDR;
    
    for (uint32_t sector = 0; sector < FW_SECTORS; sector++) {
        sd_read_block(SD_BASE_SECTOR + sector, fw_ptr);
        fw_ptr += SECTOR_SIZE;
        
        // Update LED để hiển thị progress
        led_set(0x04 | (sector & 0x03));
    }
    
    led_set(0x0F);
    
    // 3. Jump đến firmware
    // Firmware entry point = FW_BASE_ADDR
    jump_to_firmware(FW_BASE_ADDR);
}

//----------------------------------------------------------------------------
// Reset vector entry (nếu bootloader nằm ở địa chỉ 0)
//----------------------------------------------------------------------------

void __attribute__((naked, section(".init"))) _start(void) {
    asm volatile (
        // Setup stack pointer
        "la sp, _stack_top\n"
        
        // Zero-init registers
        "li x1, 0\n"
        "li x3, 0\n"
        "li x4, 0\n"
        "li x5, 0\n"
        "li x6, 0\n"
        "li x7, 0\n"
        "li x8, 0\n"
        "li x9, 0\n"
        "li x10, 0\n"
        "li x11, 0\n"
        "li x12, 0\n"
        "li x13, 0\n"
        "li x14, 0\n"
        "li x15, 0\n"
        
        // Jump to bootloader main
        "j bootloader_main\n"
    );
}
