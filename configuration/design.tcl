#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
#

set in_stream_channel [EDA::Design::createComponent in_stream_channel]

$in_stream_channel addHDLSourceFiles [list \
  "src/hdl/in_stream_channel.sv" 
]

$in_stream_channel addPythonSimFiles [list \
  "src/test/test_in_stream_channel.py" \
]

set memory_simple [EDA::Design::createComponent memory_simple]
$memory_simple addHDLSourceFiles [list \
  "src/hdl/memory_simple.sv"
  ]
  
$memory_simple addPythonSimFiles [list \
  "src/test/test_memory_simple.py" \
]

# memory_macro
set memory_macro [EDA::Design::createComponent memory_macro]
$memory_macro addHDLSourceFiles [list \
  "src/memory_macro/memory_macro.sv" \
  "src/memory_macro/asic/memory_model.sv" \
  "src/memory_macro/fpga/xilinx/bram_infered.sv" \
  "src/memory_macro/fpga/xilinx/xpm_wrapper.sv" \
  "src/memory_macro/fpga/xilinx/xpm_dual_wrapper.sv" \
  ]
