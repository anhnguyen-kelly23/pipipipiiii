/* boot_crt0.S  –  Minimal startup for PicoRV32 SD bootloader
 *
 * On reset PicoRV32 fetches from PROGADDR_RESET (default 0x0000_0000).
 * This stub:
 *   1. Sets sp to _stack_top (top of Boot BRAM = 0x0000_1000)
 *   2. Zeroes .bss
 *   3. Calls bootloader_main()
 *   4. Infinite loop (should never return)
 */

    .section .text.entry, "ax", @progbits
    .globl  boot_entry
    .type   boot_entry, @function

boot_entry:
    /* Set up stack pointer */
    la   sp, _stack_top

    /* Zero out .bss */
    la   a0, _bss_start
    la   a1, _bss_end
    beq  a0, a1, .bss_done
.bss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    blt  a0, a1, .bss_loop
.bss_done:

    /* Call the C bootloader */
    call bootloader_main

    /* Should never return, but just in case */
.halt:
    j    .halt
