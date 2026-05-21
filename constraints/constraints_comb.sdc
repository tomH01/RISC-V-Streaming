#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
set_units -time 1ps -capacitance 1fF

set_max_delay 3000 -from [all_inputs] -to [all_outputs]
set_load 0.0 [all_outputs]
