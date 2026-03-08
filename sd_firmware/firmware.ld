/*
 * Linker script cho Firmware
 * Firmware được load bởi bootloader vào địa chỉ 0x2000
 */

MEMORY
{
    /* Firmware area - loaded by bootloader from SD card */
    RAM (rwx) : ORIGIN = 0x00002000, LENGTH = 56K
}

ENTRY(_start)

/* Stack ở cuối RAM */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    /* Code section */
    .text : {
        *(.init)
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > RAM

    /* Read-only data */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > RAM

    /* Data section */
    .data : {
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    /* BSS section */
    .bss : {
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM
    
    /* Discard */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
