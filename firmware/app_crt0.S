/* app_crt0.S  –  Startup for the main application firmware
 *
 * The bootloader jumps to APP_BASE (0x0001_0000) which is this stub.
 * Sets up stack, zeroes .bss, calls main() (or firmware_main()).
 */

    .section .text.entry, "ax", @progbits
    .globl  app_entry
    .type   app_entry, @function

app_entry:
    /* Set stack pointer to top of App BRAM */
    la   sp, _stack_top

    /* Zero .bss section */
    la   a0, _bss_start
    la   a1, _bss_end
    beq  a0, a1, .bss_done
.bss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    blt  a0, a1, .bss_loop
.bss_done:

    call main       /* or rename to firmware_main, must match your C entry */

.halt:
    j    .halt
