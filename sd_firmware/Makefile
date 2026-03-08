#============================================================================
# Makefile for PicoRV32 Firmware
# Firmware được load từ SD card bởi bootloader
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
LDFLAGS = -T firmware.ld -Wl,--gc-sections -Wl,-Map=firmware.map

# Source files - thêm các file .c của bạn vào đây
SRCS = start.S main.c
OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.S=.o)

# SD Card settings
SD_DEVICE ?= /dev/sdb
SD_SECTOR ?= 100

# Targets
all: firmware.bin

firmware.elf: $(OBJS) firmware.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) -lgcc
	$(SIZE) $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@
	@echo ""
	@echo "=========================================="
	@echo "Firmware size: $$(wc -c < $@) bytes"
	@echo "Sectors needed: $$(( ($$(wc -c < $@) + 511) / 512 ))"
	@echo "=========================================="

firmware.hex: firmware.elf
	$(OBJCOPY) -O verilog $< $@

firmware.lst: firmware.elf
	$(OBJDUMP) -d -S $< > $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

# Flash firmware to SD card
flash: firmware.bin
	@echo "Writing firmware to $(SD_DEVICE) at sector $(SD_SECTOR)..."
	sudo dd if=$< of=$(SD_DEVICE) bs=512 seek=$(SD_SECTOR) conv=notrunc
	sudo sync
	@echo "Done!"

# Verify firmware on SD card
verify: firmware.bin
	@echo "Verifying firmware on $(SD_DEVICE)..."
	@SECTORS=$$(( ($$(wc -c < $<) + 511) / 512 )); \
	sudo dd if=$(SD_DEVICE) of=verify.bin bs=512 skip=$(SD_SECTOR) count=$$SECTORS 2>/dev/null; \
	if cmp -n $$(wc -c < $<) $< verify.bin; then \
		echo "✓ Verification PASSED!"; \
	else \
		echo "✗ Verification FAILED!"; \
	fi; \
	rm -f verify.bin

# Clean
clean:
	rm -f *.o *.elf *.bin *.hex *.lst *.map

# Phony targets
.PHONY: all clean flash verify

# Debug: hiển thị disassembly
dump: firmware.lst
	less $<
