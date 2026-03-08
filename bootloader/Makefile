#============================================================================
# Makefile for SD Card Bootloader
#============================================================================

# Toolchain
TOOLCHAIN_PREFIX = /opt/riscv/bin/riscv64-unknown-elf-
CC      = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP = $(TOOLCHAIN_PREFIX)objdump
SIZE    = $(TOOLCHAIN_PREFIX)size

# Flags
ARCH    = rv32i
ABI     = ilp32
CFLAGS  = -march=$(ARCH) -mabi=$(ABI) -Os -Wall -Wextra
CFLAGS += -ffreestanding -nostdlib -nostartfiles
CFLAGS += -ffunction-sections -fdata-sections
LDFLAGS = -T bootloader.ld -Wl,--gc-sections -Wl,-Map=bootloader.map

# Source files
SRCS = bootloader.c
OBJS = $(SRCS:.c=.o)

# Targets
all: bootloader.hex bootloader.bin

bootloader.elf: $(OBJS) bootloader.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) -lgcc
	$(SIZE) $@

bootloader.bin: bootloader.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Binary size: $$(wc -c < $@) bytes"

bootloader.hex: bootloader.elf
	$(OBJCOPY) -O verilog $< $@

bootloader.lst: bootloader.elf
	$(OBJDUMP) -d -S $< > $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Tạo file .mem để hard-code vào FPGA (32-bit words, little-endian)
bootloader.mem: bootloader.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@
	@echo "Memory file created with $$(wc -l < $@) words"

# Clean
clean:
	rm -f *.o *.elf *.bin *.hex *.lst *.map *.mem

# Phony targets
.PHONY: all clean

# Debug: hiển thị disassembly
dump: bootloader.lst
	cat $<
