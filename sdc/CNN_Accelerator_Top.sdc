###############################################################################
# Created by write_sdc
# Mon Jun  3 04:41:41 2024
###############################################################################
current_design CNN_Accelerator_Top
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 25.0000 
set_clock_uncertainty 0.2500 clk
set_clock_latency -source -min 4.6500 [get_clocks {clk}]
set_clock_latency -source -max 5.5700 [get_clocks {clk}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.1900 [get_ports {done}]
set_load -pin_load 0.1900 [get_ports {serial_result_valid}]
set_load -pin_load 0.1900 [get_ports {serial_result[7]}]
set_load -pin_load 0.1900 [get_ports {serial_result[6]}]
set_load -pin_load 0.1900 [get_ports {serial_result[5]}]
set_load -pin_load 0.1900 [get_ports {serial_result[4]}]
set_load -pin_load 0.1900 [get_ports {serial_result[3]}]
set_load -pin_load 0.1900 [get_ports {serial_result[2]}]
set_load -pin_load 0.1900 [get_ports {serial_result[1]}]
set_load -pin_load 0.1900 [get_ports {serial_result[0]}]
set_timing_derate -early 0.9500
set_timing_derate -late 1.0500
###############################################################################
# Design Rules
###############################################################################
set_max_transition 1.0000 [current_design]
set_max_fanout 16.0000 [current_design]
