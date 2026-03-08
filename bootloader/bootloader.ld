/*
 * Linker script cho SD Card Bootloader
 * 
 * Memory Layout:
 *   0x0000_0000 - 0x0000_1FFF : Bootloader (8KB max)
 *   0x0000_2000 - onwards     : Firmware (được load từ SD card)
 */

MEMORY
{
    /* Bootloader ROM - 8KB */
    BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    
    /* Bootloader RAM/Stack - nhỏ, dùng tạm */
    BOOTRAM (rwx) : ORIGIN = 0x00001800, LENGTH = 2K
}

ENTRY(_start)

SECTIONS
{
    /* Code section */
    .text : {
        *(.init)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > BOOTROM

    /* Data section */
    .data : {
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _edata = .;
    } > BOOTRAM AT > BOOTROM
    
    _sidata = LOADADDR(.data);

    /* BSS section */
    .bss : {
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > BOOTRAM

    /* Stack - đặt ở cuối BOOTRAM */
    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 512;  /* 512 bytes stack */
        _stack_top = .;
    } > BOOTRAM
    
    /* Discard debug info */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}

