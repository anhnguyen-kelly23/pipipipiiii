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

