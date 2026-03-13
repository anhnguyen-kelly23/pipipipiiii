/*
 * bootloader.ld — Linker script for PicoRV32 SD bootloader
 *
 * Memory layout:
 *   BOOTROM  0x0000_0000  4 KB  code + rodata (read-only BRAM, pre-loaded hex)
 *   BL_RAM   0x0001_F000  4 KB  bootloader .data/.bss + stack (top of App BRAM)
 *
 * The firmware load area is 0x0001_0000 – 0x0001_EFFF (60 KB).
 * BL_RAM is placed at the TOP of App BRAM to avoid collision with
 * the firmware being copied into the bottom of App BRAM.
 *
 *   App BRAM 64 KB layout during boot:
 *   ┌──────────────────────┐ 0x0002_0000
 *   │  ← stack (grows ↓)  │
 *   │  bootloader .bss     │ ← sbuf[512], g_sdhc, etc.
 *   │  bootloader .data    │
 *   ├──────────────────────┤ 0x0001_F000
 *   │                      │
 *   │  (firmware load area │
 *   │   max 60 KB)         │
 *   │                      │
 *   └──────────────────────┘ 0x0001_0000
 */

MEMORY
{
    BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    BL_RAM  (rw)  : ORIGIN = 0x0001F000, LENGTH = 4K
}

ENTRY(boot_entry)

SECTIONS
{
    .text.entry : { *(.text.entry) } > BOOTROM
    .text       : { *(.text*)      } > BOOTROM
    .rodata     : { *(.rodata*)    } > BOOTROM
    .data       : { *(.data*)      } > BL_RAM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > BL_RAM

    _stack_top = ORIGIN(BL_RAM) + LENGTH(BL_RAM);  /* 0x0002_0000 */
}

