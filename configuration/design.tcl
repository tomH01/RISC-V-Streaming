#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
#



# ------
# Common
# ------

set skid_buffer [EDA::Design::createComponent skid_buffer]

$skid_buffer addHDLSourceFiles [list \
  "src/hdl/common/flow_control/skid_buffer.sv" 
]

$skid_buffer addPythonSimFiles [list \
  "src/test/common/flow_control/test_skid_buffer.py" \
]


set fwft_fifo [EDA::Design::createComponent fwft_fifo]

$fwft_fifo addHDLSourceFiles [list \
  "src/hdl/common/mem/fwft_fifo.sv" \
]

$fwft_fifo addPythonSimFiles [list \
  "src/test/common/mem/test_fwft_fifo.py" \
]


set rr_arbiter [EDA::Design::createComponent rr_arbiter]

$rr_arbiter addHDLSourceFiles [list \
  "src/hdl/common/arb/rr_arbiter.sv" \
]

$rr_arbiter addPythonSimFiles [list \
  "src/test/common/arb/test_rr_arbiter.py" \
]



# -------
# Ingress
# -------

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
  "src/hdl/common/flow_control/skid_buffer.sv" \
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

set job_manager_wrapper [EDA::Design::createComponent job_manager_wrapper]

$job_manager_wrapper addHDLSourceFiles [list \
  "src/test/dma/egress/job_manager_wrapper.sv" \
  "src/hdl/dma/egress/job_manager.sv" \
  "src/hdl/dma/egress/job_if.sv" \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/common/arb/rr_arbiter.sv" \
  "src/hdl/common/flow_control/skid_buffer.sv" \
]

$job_manager_wrapper addPythonSimFiles [list \
  "src/test/dma/egress/test_job_manager.py" \
]


set l2_allocator_wrapper [EDA::Design::createComponent l2_allocator_wrapper]

$l2_allocator_wrapper addHDLSourceFiles [list \
  "src/test/dma/egress/l2_allocator_wrapper.sv" \
  "src/hdl/dma/egress/l2_allocator.sv" \
  "src/hdl/dma/egress/job_if.sv" \
]

$l2_allocator_wrapper addPythonSimFiles [list \
  "src/test/dma/egress/test_l2_allocator.py" \
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
