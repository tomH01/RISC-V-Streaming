#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
set_units -time 1ps -capacitance 1fF

#==============
# Clock Network
#==============
# Default 100 MHz
#set REF_CLK_PERIOD 10000

set REF_CLK_PERIOD 5000

create_clock -name ref_clock -period $REF_CLK_PERIOD [get_ports clk_i]

set_clock_transition -min  650 -rise [get_clocks ref_clock]
set_clock_transition -max 1300 -rise [get_clocks ref_clock]
set_clock_transition -min  650 -fall [get_clocks ref_clock]
set_clock_transition -max 1300 -fall [get_clocks ref_clock]

set_clock_uncertainty 150 [get_clocks ref_clock]

#==============
# Reset Network
#==============
set_ideal_network [get_nets rst_ni]

#============
# Input Ports
#============
# Drive Resistances
set_drive 0.0 [remove_from_collection [all_inputs] clk_i]
# Delays
set_input_delay 0 -clock [get_clocks ref_clock] [remove_from_collection [all_inputs] clk_i]

#=============
# Output Ports
#=============
# Load Capacitances
set_load 0.0 [all_outputs]
# Delays
set_output_delay 0 -clock [get_clocks ref_clock] [all_outputs]

#============
# False Paths
#============
set_false_path -from [get_ports rst_ni]
