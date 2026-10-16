# In an open Vivado project with bad_apple_top.vhd already added:
# source C:/your/path/bad_apple_fpga/simulate.tcl
set here [file dirname [file normalize [info script]]]
add_files -fileset sim_1 [file join $here tb_bad_apple.vhd]
set_property file_type {VHDL 2008} [get_files *tb_bad_apple.vhd]
set_property top tb_bad_apple [get_filesets sim_1]
launch_simulation
run 300 ms
