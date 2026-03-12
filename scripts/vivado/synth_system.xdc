## XDC File for Arty A7-100T Board

## ============================================
## Clock Signal (100 MHz)
## ============================================
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.00 [get_ports clk]

## ============================================
## Reset Button (Red dedicated button)
## ============================================
set_property PACKAGE_PIN C2 [get_ports {resetn_btn}]
set_property IOSTANDARD LVCMOS33 [get_ports {resetn_btn}]

## ============================================
## UART - USB-UART Bridge (FTDI Chip)
## ============================================
set_property PACKAGE_PIN D10 [get_ports {uart_tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx}]

set_property PACKAGE_PIN A9 [get_ports {uart_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx}]

## ============================================
## Switches (SW0-SW3) - Input
## CPU đọc qua 0x2000_0000
## ============================================
set_property PACKAGE_PIN A8  [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
set_property PACKAGE_PIN C11 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]
set_property PACKAGE_PIN C10 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]
set_property PACKAGE_PIN A10 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]

## ============================================
## Buttons (BTN0-BTN3) - Input
## CPU đọc qua 0x2000_0004
## ============================================
set_property PACKAGE_PIN D9  [get_ports {btn[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[0]}]
set_property PACKAGE_PIN C9  [get_ports {btn[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[1]}]
set_property PACKAGE_PIN B9  [get_ports {btn[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[2]}]
set_property PACKAGE_PIN B8  [get_ports {btn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[3]}]

## ============================================
## out_byte[7:0] → LED
## CPU ghi qua 0x1000_0000
## LD0-LD3: RGB LED Blue channel
## LD4-LD7: Standard single-color LED
## ============================================
# Bit 0 → LD0 Blue
set_property PACKAGE_PIN E1 [get_ports {out_byte[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[0]}]
# Bit 1 → LD1 Blue
set_property PACKAGE_PIN G4 [get_ports {out_byte[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[1]}]
# Bit 2 → LD2 Blue
set_property PACKAGE_PIN H4 [get_ports {out_byte[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[2]}]
# Bit 3 → LD3 Blue
set_property PACKAGE_PIN K2 [get_ports {out_byte[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[3]}]
# Bit 4 → LD4
set_property PACKAGE_PIN H5 [get_ports {out_byte[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[4]}]
# Bit 5 → LD5
set_property PACKAGE_PIN J5 [get_ports {out_byte[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[5]}]
# Bit 6 → LD6
set_property PACKAGE_PIN T9 [get_ports {out_byte[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[6]}]
# Bit 7 → LD7
set_property PACKAGE_PIN T10 [get_ports {out_byte[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte[7]}]

## ============================================
## Control Signals
## ============================================
# Trap → LD0 Green
set_property PACKAGE_PIN F6 [get_ports {trap}]
set_property IOSTANDARD LVCMOS33 [get_ports {trap}]

# Out_byte_en → LD1 Green
set_property PACKAGE_PIN J4 [get_ports {out_byte_en}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_byte_en}]

## ============================================
## Configuration
## ============================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## SD Card SPI – Pmod JA (hàng trên)
## Phải → Trái: VCC, GND, CLK, MISO, MOSI, CS

# JA1 (G13) → CS_N
set_property PACKAGE_PIN G13 [get_ports {sd_cs_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_cs_n}]

# JA2 (B11) → MOSI
set_property PACKAGE_PIN B11 [get_ports {sd_mosi}]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_mosi}]

# JA3 (A11) → MISO
set_property PACKAGE_PIN A11 [get_ports {sd_miso}]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_miso}]

# JA4 (D12) → SCK
set_property PACKAGE_PIN D12 [get_ports {sd_sck}]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_sck}]