MEMORY {
    BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    APPRAM  (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    .text : {
        *(.text.entry)
        *(.text*)
        *(.rodata*)
    } > BOOTROM

    .data : {
        *(.data*)
    } > APPRAM

    .bss : {
        *(.bss*)
        *(COMMON)
    } > APPRAM
}

PROVIDE(_stack_top = ORIGIN(APPRAM) + LENGTH(APPRAM));
