# =============================================================================
# start.S - Startup code cho Firmware
# Entry point: _start (tại địa chỉ 0x2000)
# =============================================================================

.section .init
.global _start

_start:
    # Setup stack pointer
    la sp, _stack_top
    
    # Zero-init registers (optional nhưng good practice)
    li x1, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0

    # Zero-init BSS section
    la a0, _sbss
    la a1, _ebss
    bge a0, a1, bss_done
bss_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, bss_loop
bss_done:

    # Call main
    call main

    # Infinite loop if main returns
halt:
    j halt
