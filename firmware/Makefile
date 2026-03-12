# =============================================================
# Makefile – PicoRV32 SD Bootloader + Application
#
# Requirements:
#   riscv32-unknown-elf-gcc  (or riscv64-unknown-elf-gcc -march=rv32i)
#   python3
#   make
# =============================================================

CROSS 	?= riscv64-unknown-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump

# Common RISC-V flags for bare-metal RV32I (matches PicoRV32 default)
ARCH_FLAGS = -march=rv32i -mabi=ilp32

CFLAGS_COMMON = $(ARCH_FLAGS) -Os -g \
    -ffreestanding -fno-builtin \
    -Wall -Wextra \
    -nostdlib -nostartfiles

# -------------------------------------------------------
# 1. BOOTLOADER  (runs from Boot BRAM @ 0x0000_0000)
# -------------------------------------------------------
BOOT_SRCS  = boot_crt0.S bootloader.c
BOOT_LD    = bootloader.ld
BOOT_ELF   = bootloader.elf
BOOT_BIN   = bootloader.bin
BOOT_HEX   = bootloader.hex
BOOT_DUMP  = bootloader.dis

.PHONY: bootloader
bootloader: $(BOOT_HEX)

$(BOOT_ELF): $(BOOT_SRCS) $(BOOT_LD)
	$(CC) $(CFLAGS_COMMON) -T $(BOOT_LD) -o $@ $(BOOT_SRCS)
	@echo "[BOOT] Size:"
	@$(CROSS)-size $@

$(BOOT_BIN): $(BOOT_ELF)
	$(OBJCOPY) -O binary $< $@

$(BOOT_HEX): $(BOOT_BIN)
	python3 makehex.py $< > $@
	@echo "[BOOT] bootloader.hex ready → copy to Vivado project as bootloader.hex"

$(BOOT_DUMP): $(BOOT_ELF)
	$(OBJDUMP) -d -S $< > $@

# -------------------------------------------------------
# 2. APPLICATION FIRMWARE  (loaded into App BRAM @ 0x0001_0000)
# -------------------------------------------------------
# List your application source files here:
APP_SRCS   = app_crt0.S ../scripts/vivado/firmware.c
APP_LD     = firmware.ld
APP_ELF    = firmware.elf
APP_BIN    = firmware.bin
APP_DUMP   = firmware.dis

.PHONY: firmware
firmware: $(APP_BIN)

$(APP_ELF): $(APP_SRCS) $(APP_LD)
	$(CC) $(CFLAGS_COMMON) -T $(APP_LD) -o $@ $(APP_SRCS)
	@echo "[APP] Size:"
	@$(CROSS)-size $@

$(APP_BIN): $(APP_ELF)
	python3 wrap_firmware.py $< $@
	@echo "[APP] firmware.bin ready (with 4-byte size header)"
	@echo "      Write to SD card:  dd if=$@ of=/dev/sdX bs=512 seek=2048 conv=notrunc"

$(APP_DUMP): $(APP_ELF)
	$(OBJDUMP) -d -S $< > $@

# -------------------------------------------------------
# 3. Write firmware to SD card
#    WARNING: Replace /dev/sdX with your actual SD device!
# -------------------------------------------------------
SD_DEV ?= /dev/null   # Override: make write-sd SD_DEV=/dev/sdb

.PHONY: write-sd
write-sd: $(APP_BIN)
	@if [ "$(SD_DEV)" = "/dev/null" ]; then \
	    echo "ERROR: set SD_DEV=<device>  e.g.  make write-sd SD_DEV=/dev/sdb"; \
	    exit 1; \
	fi
	@echo "Writing $(APP_BIN) to $(SD_DEV) at sector 2048 (1 MB offset)..."
	sudo dd if=$(APP_BIN) of=$(SD_DEV) bs=512 seek=2048 conv=notrunc oflag=sync
	@echo "Done."

# -------------------------------------------------------
# 4. Helpers
# -------------------------------------------------------
.PHONY: all clean disasm

all: bootloader firmware

disasm: $(BOOT_DUMP) $(APP_DUMP)

clean:
	rm -f *.elf *.bin *.hex *.dis
