MEMORY
{
    BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    APPRAM  (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

ENTRY(boot_entry)

SECTIONS
{
    .text.entry : { *(.text.entry) } > BOOTROM
    .text       : { *(.text*)      } > BOOTROM
    .rodata     : { *(.rodata*)    } > BOOTROM
    .data       : { *(.data*)      } > APPRAM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > APPRAM

    _stack_top = ORIGIN(APPRAM) + LENGTH(APPRAM);
}
