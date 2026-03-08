/*
 * main.c - Firmware chính cho PicoRV32
 * 
 * Firmware này được load từ SD card bởi bootloader.
 * Entry point: 0x00002000
 */

#include <stdint.h>

//============================================================================
// Memory-mapped Registers
//============================================================================

// LEDs (address từ system.v của bạn)
#define REG_LEDS        (*(volatile uint32_t*)0x10000000)

// UART
#define REG_UART_DATA   (*(volatile uint32_t*)0x20000008)
#define REG_UART_DIV    (*(volatile uint32_t*)0x20000004)

// Switches và Buttons
#define REG_SWITCHES    (*(volatile uint32_t*)0x20000000)
#define REG_BUTTONS     (*(volatile uint32_t*)0x20000004)

//============================================================================
// UART Functions
//============================================================================

void uart_init(uint32_t baud_div) {
    REG_UART_DIV = baud_div;
}

void uart_putchar(char c) {
    REG_UART_DATA = c;
    // Simple delay - có thể cần điều chỉnh
    for (volatile int i = 0; i < 1000; i++);
}

void uart_print(const char *s) {
    while (*s) {
        if (*s == '\n')
            uart_putchar('\r');
        uart_putchar(*s++);
    }
}

void uart_print_hex(uint32_t val, int digits) {
    for (int i = digits - 1; i >= 0; i--) {
        int digit = (val >> (i * 4)) & 0xF;
        uart_putchar(digit < 10 ? '0' + digit : 'A' + digit - 10);
    }
}

//============================================================================
// LED Functions
//============================================================================

void led_set(uint8_t value) {
    REG_LEDS = value;
}

void led_pattern(uint8_t pattern, int delay) {
    led_set(pattern);
    for (volatile int i = 0; i < delay; i++);
}

//============================================================================
// Simple Delay
//============================================================================

void delay(uint32_t cycles) {
    for (volatile uint32_t i = 0; i < cycles; i++);
}

//============================================================================
// Main Function
//============================================================================

void main(void) {
    // Init UART (100MHz / 115200 ≈ 868)
    uart_init(868);
    
    // Print boot message
    uart_print("\n\n");
    uart_print("================================\n");
    uart_print("  PicoRV32 Firmware Started!\n");
    uart_print("  Loaded from SD Card\n");
    uart_print("================================\n\n");
    
    // Show firmware address
    uart_print("Entry point: 0x");
    uart_print_hex(0x2000, 8);
    uart_print("\n");
    
    // LED startup pattern
    for (int i = 0; i < 3; i++) {
        led_set(0xFF);
        delay(500000);
        led_set(0x00);
        delay(500000);
    }
    
    uart_print("Running main loop...\n\n");
    
    // Main loop
    uint32_t counter = 0;
    while (1) {
        // LED chạy theo counter
        led_set(counter & 0xFF);
        
        // In ra mỗi ~1 giây (tùy tần số clock)
        if ((counter & 0xFFFFF) == 0) {
            uart_print("Counter: 0x");
            uart_print_hex(counter, 8);
            uart_print("\n");
        }
        
        counter++;
        delay(10000);
    }
}
