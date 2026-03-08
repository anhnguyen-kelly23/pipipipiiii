read_verilog system.v
# ── SD Card modules ──────────────────────────────────────────────────
read_verilog sd_spi_master.v
read_verilog sd_controller.v
read_verilog sd_read_block.v
read_verilog sd_bootloader.v
read_verilog spi_arbiter.v
read_verilog ram_arbiter.v



read_verilog ../../picorv32.v
read_verilog ../../picosoc/simpleuart.v

read_verilog ../../picosoc/tinyjambu/tinyjambu_core.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_datapath.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_nlfsr.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_fsm.v

read_verilog ../../picosoc/Xoodyak_old/xoodoo.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_n_rounds.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_rc.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_round.v
read_verilog ../../picosoc/Xoodyak_old/xoodyakcore.v



read_verilog ../../picosoc/GIFT_COFB/cofb_core.v
read_verilog ../../picosoc/GIFT_COFB/double_half_block.v
read_verilog ../../picosoc/GIFT_COFB/feedback_G.v
read_verilog ../../picosoc/GIFT_COFB/gift128_addroundkey.v
read_verilog ../../picosoc/GIFT_COFB/gift128_encrypt_top.v
read_verilog ../../picosoc/GIFT_COFB/gift128_keyschedule.v
read_verilog ../../picosoc/GIFT_COFB/gift128_permbits.v
read_verilog ../../picosoc/GIFT_COFB/gift128_round.v
read_verilog ../../picosoc/GIFT_COFB/gift128_roundconst.v
read_verilog ../../picosoc/GIFT_COFB/gift128_subcells.v
read_verilog ../../picosoc/GIFT_COFB/padding.v
read_verilog ../../picosoc/GIFT_COFB/pho.v
read_verilog ../../picosoc/GIFT_COFB/pho1.v
read_verilog ../../picosoc/GIFT_COFB/phoprime.v
read_verilog ../../picosoc/GIFT_COFB/triple_half_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_topbar_block.v


read_xdc synth_system.xdc

synth_design -part XC7A100TCSG324-1 -top system
opt_design
place_design
route_design

report_utilization -hierarchical -file report_utilization.rpt
report_timing

write_verilog -force synth_system.v
write_bitstream -force synth_system.bit
# write_mem_info -force synth_system.mmi
# ── Full system reports ──────────────────────────────────────────────

# ── Per-core utilization reports ─────────────────────────────────────
report_utilization -hierarchical -hierarchical_depth 3 -file report_util_full.txt

report_utilization -cells [get_cells u_jambu]    -file report_util_tinyjambu.txt
report_utilization -cells [get_cells u_xoodyak]  -file report_util_xoodyak.txt
report_utilization -cells [get_cells u_giftcofb] -file report_util_giftcofb.txt

# ── Per-core timing reports ──────────────────────────────────────────
report_timing -from [get_cells u_jambu/*]    -to [get_cells u_jambu/*]    -max_paths 10 -file report_timing_tinyjambu.txt
report_timing -from [get_cells u_xoodyak/*]  -to [get_cells u_xoodyak/*]  -max_paths 10 -file report_timing_xoodyak.txt
report_timing -from [get_cells u_giftcofb/*] -to [get_cells u_giftcofb/*] -max_paths 10 -file report_timing_giftcofb.txt

# ── Summary timing ───────────────────────────────────────────────────
report_timing_summary -file report_timing_summary.txt

