#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
#



# -------
# Ingress
# -------

set in_stream_channel [EDA::Design::createComponent in_stream_channel]

$in_stream_channel addHDLSourceFiles [list \
  "src/hdl/dma/ingress/in_stream_channel.sv" 
]

$in_stream_channel addPythonSimFiles [list \
  "src/test/dma/ingress/test_in_stream_channel.py" \
]


set buffer_pool [EDA::Design::createComponent buffer_pool]

$buffer_pool addHDLSourceFiles [list \
  "src/hdl/dma/ingress/buffer_pool.sv" \
  "src/hdl/memory/buffer_sram_macro.sv" \
]

$buffer_pool addPythonSimFiles [list \
  "src/test/dma/ingress/test_buffer_pool.py" \
]


set ingress_crossbar [EDA::Design::createComponent ingress_crossbar]

$ingress_crossbar addHDLSourceFiles [list \
  "src/hdl/dma/ingress/ingress_crossbar.sv" \
]

$ingress_crossbar addPythonSimFiles [list \
  "src/test/dma/ingress/test_ingress_crossbar.py" \
]


set alloc_manager [EDA::Design::createComponent alloc_manager]

$alloc_manager addHDLSourceFiles [list \
  "src/hdl/dma/ingress/alloc_manager.sv" \
]


set ingress_top [EDA::Design::createComponent ingress_top]

$ingress_top addHDLSourceFiles [list \
  "src/hdl/dma/ingress/ingress_top.sv" \
  "src/hdl/dma/ingress/in_stream_channel.sv" \
  "src/hdl/dma/ingress/ingress_crossbar.sv" \
  "src/hdl/dma/ingress/alloc_manager.sv" \
]

$ingress_top addPythonSimFiles [list \
  "src/test/dma/ingress/test_ingress_top.py" \
]



set memory_simple [EDA::Design::createComponent memory_simple]

$memory_simple addHDLSourceFiles [list \
  "src/hdl/memory/memory_simple.sv"
  ]
  
$memory_simple addPythonSimFiles [list \
  "src/test/test_memory_simple.py" \
]



# ------
# Egress
# ------

set fwft_fifo [EDA::Design::createComponent fwft_fifo]

$fwft_fifo addHDLSourceFiles [list \
  "src/hdl/dma/egress/fwft_fifo.sv" \
]

$fwft_fifo addPythonSimFiles [list \
  "src/test/dma/egress/test_fwft_fifo.py" \
]


set rr_arbiter [EDA::Design::createComponent rr_arbiter]

$rr_arbiter addHDLSourceFiles [list \
  "src/hdl/dma/egress/rr_arbiter.sv" \
]

$rr_arbiter addPythonSimFiles [list \
  "src/test/dma/egress/test_rr_arbiter.py" \
]



# ---
# DMA
# ---

set control [EDA::Design::createComponent control]

$control addHDLSourceFiles [list \
  "src/hdl/dma/control.sv" \
]

$control addPythonSimFiles [list \
  "src/test/dma/test_control.py" \
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
