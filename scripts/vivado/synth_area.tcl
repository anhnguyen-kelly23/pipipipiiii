read_verilog ../../picorv32.v
read_xdc synth_area.xdc

synth_design -part XC7A100TCSG324-1 -top picorv32_axi
opt_design -resynth_seq_area

report_utilization
report_timing
