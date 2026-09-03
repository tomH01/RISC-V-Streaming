#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
#


set tools [list \
  "src/test/tools/addr_generator_models.py" \
  "src/test/tools/config_randomizer.py" \
]

set drivers [list \
  "src/test/drivers/base_driver.py" \
  "src/test/drivers/ctrl_drivers.py" \
  "src/test/drivers/data_drivers.py" \
  "src/test/drivers/dma_driver.py" \
  "src/test/drivers/control_driver.py" \
]

set use_case [list \
  "src/test/use_case/sensor_set.py" \
  "src/test/use_case/stream.py" \
]

set ingress_hdl [list \
  "src/hdl/common/flow_control/skid_buffer.sv" \
  "src/hdl/dma/ingress/ingress_crossbar.sv" \
  "src/hdl/dma/ingress/alloc_manager.sv" \
  "src/hdl/dma/ingress/ingress_top.sv" \
]

set egress_hdl [list \
  "src/hdl/common/flow_control/skid_buffer.sv" \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/common/mem/fifo.sv" \
  "src/hdl/common/arb/rr_arbiter.sv" \
  "src/hdl/dma/egress/job_if.sv" \
  "src/hdl/dma/egress/job_manager.sv" \
  "src/hdl/dma/egress/l2_allocator.sv" \
  "src/hdl/dma/egress/meta.sv" \
  "src/hdl/dma/egress/strided_addr_gen.sv" \
  "src/hdl/dma/egress/address_generator.sv" \
  "src/hdl/dma/egress/egress_top.sv" \
]

set egress_blockwise_hdl [list \
  "src/hdl/common/flow_control/skid_buffer.sv" \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/common/mem/fifo.sv" \
  "src/hdl/common/arb/rr_arbiter.sv" \
  "src/hdl/dma/egress/blockwise/job_if.sv" \
  "src/hdl/dma/egress/blockwise/meta_if.sv" \
  "src/hdl/dma/egress/blockwise/job_manager.sv" \
  "src/hdl/dma/egress/blockwise/l2_allocator.sv" \
  "src/hdl/dma/egress/blockwise/meta_writer.sv" \
  "src/hdl/dma/egress/strided_addr_gen.sv" \
  "src/hdl/dma/egress/blockwise/address_generator.sv" \
  "src/hdl/dma/egress/blockwise/egress_top.sv" \
]

set dma_hdl [concat \
  $ingress_hdl \
  $egress_hdl \
  [list \
    "src/hdl/memory/buffer_sram_macro.sv" \
    "src/hdl/dma/buffer_pool.sv" \
    "src/hdl/dma/control.sv" \
    "src/hdl/dma/stream_generator.sv" \
    "src/hdl/dma/dma_top.sv" \
  ] 
]

set dma_blockwise_hdl [concat \
  $ingress_hdl \
  $egress_blockwise_hdl \
  [list \
    "src/hdl/memory/buffer_sram_macro.sv" \
    "src/hdl/dma/buffer_pool.sv" \
    "src/hdl/dma/stream_generator.sv" \
    "src/hdl/dma/blockwise/control.sv" \
    "src/hdl/dma/blockwise/dma_top.sv" \
  ] 
]

set cc [list \
  "src/hdl/common/cc/cf_math_pkg.sv" \
  "src/hdl/common/cc/lzc.sv" \
  "src/hdl/common/cc/addr_decode.sv" \
  "src/hdl/common/cc/addr_decode_dync.sv" \
  "src/hdl/common/cc/rr_arb_tree.sv" \
  "src/hdl/common/cc/spill_register.sv" \
  "src/hdl/common/cc/spill_register_flushable.sv" \
  "src/hdl/common/cc/fifo_v3.sv" \
  "src/hdl/common/cc/fall_through_register.sv" \
  "src/hdl/common/cc/stream_fifo.sv" \
  "src/hdl/common/cc/stream_join.sv" \
  "src/hdl/common/cc/stream_join_dynamic.sv" \
  "src/hdl/common/cc/stream_fork.sv" \
  "src/hdl/common/cc/stream_fork_dynamic.sv" \
  "src/hdl/common/cc/stream_mux.sv" \
  "src/hdl/common/cc/stream_demux.sv" \
  "src/hdl/common/cc/stream_xbar.sv" \
]

set axi [list \
  "src/hdl/common/axi/axi_pkg.sv" \
  "src/hdl/common/axi/axi_lite_to_apb.sv" \
  "src/hdl/common/axi/axi_to_detailed_mem.sv" \
  "src/hdl/common/axi/axi_to_mem.sv" \
]

set apb [list \
  "src/hdl/common/apb/apb_pkg.sv" \
]

set l2_subsystem_hdl [concat \
  $cc \
  [list \
    "src/hdl/memory/l2_sram_macro.sv" \
    "src/hdl/top/sram_interconnect.sv" \
    "src/hdl/top/l2_subsystem.sv" \
  ] 
]

set l2_subsystem_blockwise_hdl [concat \
  $cc \
  [list \
    "src/hdl/memory/blockwise/l2_sram_macro.sv" \
    "src/hdl/top/blockwise/sram_interconnect.sv" \
    "src/hdl/top/blockwise/l2_subsystem.sv" \
  ] 
]

# ------
# Common
# ------

set skid_buffer [EDA::Design::createComponent skid_buffer]

$skid_buffer addHDLSourceFiles [list \
  "src/hdl/common/flow_control/skid_buffer.sv" 
]

$skid_buffer addPythonSimFiles [concat [list \
  "src/test/common/flow_control/test_skid_buffer.py" \
]]


set fifo [EDA::Design::createComponent fifo]

$fifo addHDLSourceFiles [list \
  "src/hdl/common/mem/fifo.sv" \
]

$fifo addPythonSimFiles [concat [list \
  "src/test/common/mem/test_fifo.py" \
]]


set fwft_fifo [EDA::Design::createComponent fwft_fifo]

$fwft_fifo addHDLSourceFiles [list \
  "src/hdl/common/mem/fwft_fifo.sv" \
]

$fwft_fifo addPythonSimFiles [concat [list \
  "src/test/common/mem/test_fwft_fifo.py" \
]]


set rr_arbiter [EDA::Design::createComponent rr_arbiter]

$rr_arbiter addHDLSourceFiles [list \
  "src/hdl/common/arb/rr_arbiter.sv" \
]

$rr_arbiter addPythonSimFiles [concat [list \
  "src/test/common/arb/test_rr_arbiter.py" \
]]



# -------
# Ingress
# -------

set ingress_crossbar [EDA::Design::createComponent ingress_crossbar]

$ingress_crossbar addHDLSourceFiles [list \
  "src/hdl/dma/ingress/ingress_crossbar.sv" \
]

$ingress_crossbar addPythonSimFiles [concat [list \
  "src/test/dma/ingress/test_ingress_crossbar.py" \
]]


set alloc_manager [EDA::Design::createComponent alloc_manager]

$alloc_manager addHDLSourceFiles [list \
  "src/hdl/dma/ingress/alloc_manager.sv" \
]


set ingress_top [EDA::Design::createComponent ingress_top]

$ingress_top addHDLSourceFiles $ingress_hdl

$ingress_top addPythonSimFiles [concat [list \
  "src/test/dma/ingress/test_ingress_top.py" \
]]


set memory_simple [EDA::Design::createComponent memory_simple]

$memory_simple addHDLSourceFiles [list \
  "src/hdl/memory/memory_simple.sv"
  ]
  
$memory_simple addPythonSimFiles [concat [list \
  "src/test/test_memory_simple.py" \
]]



# ------
# Egress
# ------

set job_manager_wrapper [EDA::Design::createComponent job_manager_wrapper]

$job_manager_wrapper addHDLSourceFiles [list \
  "src/hdl/dma/egress/job_if.sv" \
  "src/hdl/dma/egress/job_manager.sv" \
  "src/test/dma/egress/job_manager_wrapper.sv" \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/common/arb/rr_arbiter.sv" \
  "src/hdl/common/flow_control/skid_buffer.sv" \
]

$job_manager_wrapper addPythonSimFiles [concat [list \
  "src/test/dma/egress/test_job_manager.py" \
]]


set l2_allocator_wrapper [EDA::Design::createComponent l2_allocator_wrapper]

$l2_allocator_wrapper addHDLSourceFiles [list \
  "src/hdl/dma/egress/job_if.sv" \
  "src/hdl/dma/egress/l2_allocator.sv" \
  "src/test/dma/egress/l2_allocator_wrapper.sv" \
]

$l2_allocator_wrapper addPythonSimFiles [concat [list \
  "src/test/dma/egress/test_l2_allocator.py" \
]]


set meta [EDA::Design::createComponent meta]

$meta addHDLSourceFiles [list \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/dma/egress/meta.sv" \
]

$meta addPythonSimFiles [concat $tools $drivers [list \
  "src/test/dma/egress/test_meta.py" \
]]


set strided_addr_gen [EDA::Design::createComponent strided_addr_gen]

$strided_addr_gen addHDLSourceFiles [list \
  "src/hdl/dma/egress/strided_addr_gen.sv" \
]

$strided_addr_gen addPythonSimFiles [concat $tools $drivers [list \
  "src/test/dma/egress/test_strided_addr_gen.py" \
]]


set address_generator_wrapper [EDA::Design::createComponent address_generator_wrapper]
$address_generator_wrapper addHDLSourceFiles [list \
  "src/hdl/dma/egress/job_if.sv" \
  "src/hdl/common/flow_control/skid_buffer.sv" \
  "src/hdl/common/mem/fwft_fifo.sv" \
  "src/hdl/dma/egress/strided_addr_gen.sv" \
  "src/hdl/dma/egress/address_generator.sv" \
  "src/test/dma/egress/address_generator_wrapper.sv" \
]

$address_generator_wrapper addPythonSimFiles [concat $tools $drivers [list \
  "src/test/dma/egress/test_address_generator.py" \
]]



# ---
# DMA
# ---

set control [EDA::Design::createComponent control]

$control addHDLSourceFiles [list \
  "src/hdl/dma/control.sv" \
]

$control addPythonSimFiles [concat $tools $drivers [list \
  "src/test/dma/test_control.py" \
]]


set dma_top [EDA::Design::createComponent dma_top]

$dma_top addHDLSourceFiles $dma_hdl 


$dma_top addPythonSimFiles [concat $tools $drivers [list \
  "src/test/dma/test_dma_top.py" \
]]


set buffer_pool [EDA::Design::createComponent buffer_pool]

$buffer_pool addHDLSourceFiles [list \
  "src/hdl/memory/buffer_sram_macro.sv" \
  "src/hdl/dma/buffer_pool.sv" \
]

$buffer_pool addPythonSimFiles [concat [list \
  "src/test/dma/test_buffer_pool.py" \
]]


set stream_generator [EDA::Design::createComponent stream_generator]

$stream_generator addHDLSourceFiles [list \
  "src/hdl/dma/stream_generator.sv" \
]

$stream_generator addPythonSimFiles [concat [list \
  "src/test/dma/test_stream_generator.py" \
]]



# ---
# top
# ---

set top [EDA::Design::createComponent top]

$top addHDLSourceFiles [concat \
  $cc \
  $dma_hdl \
  $l2_subsystem_hdl \
  [list \
    "src/hdl/top/performance_monitor.sv" \
    "src/hdl/top/top.sv" \
  ]
]

$top addHDLIncludeDirectories [list \
  "src/hdl/include" \
]

$top addPythonSimFiles [concat $tools $drivers $use_case [list \
  "src/test/top/test_top.py" \
]]



set top_blockwise [EDA::Design::createComponent top_blockwise]

$top_blockwise addHDLSourceFiles [concat \
  $cc \
  $dma_blockwise_hdl \
  $l2_subsystem_blockwise_hdl \
  [list \
    "src/hdl/top/performance_monitor.sv" \
    "src/hdl/top/blockwise/top.sv" \
  ]
]

$top_blockwise addHDLIncludeDirectories [list \
  "src/hdl/include" \
]

$top_blockwise addPythonSimFiles [concat $tools $drivers $use_case [list \
  "src/test/top/blockwise/test_top.py" \
]]


set l2_subsystem [EDA::Design::createComponent l2_subsystem]

$l2_subsystem addHDLSourceFiles $l2_subsystem_hdl

$l2_subsystem addHDLIncludeDirectories [list \
  "src/hdl/include" \
]

$l2_subsystem addPythonSimFiles [concat $tools $drivers [list \
  "src/test/top/test_l2_subsystem.py" \
]]


set performance_monitor [EDA::Design::createComponent performance_monitor]

$performance_monitor addHDLSourceFiles [list \
  "src/hdl/top/performance_monitor.sv" \
]

$performance_monitor addPythonSimFiles [concat $tools $drivers [list \
  "src/test/top/test_performance_monitor.py" \
]]


set top_axi_wrapper [EDA::Design::createComponent top_axi_wrapper]

$top_axi_wrapper addHDLSourceFiles [concat \
  $cc \
  $axi \
  $apb \
  $dma_hdl \
  $l2_subsystem_hdl \
  [list \
    "src/hdl/top/performance_monitor.sv" \
    "src/hdl/top/top.sv" \
    "src/hdl/top/top_axi_wrapper.sv" \
  ]
]

$top_axi_wrapper addHDLIncludeDirectories [list \
  "src/hdl/include" \
]

$top_axi_wrapper addPythonSimFiles [concat $tools $drivers [list \
  "src/test/top/test_top_axi_wrapper.py" \
]]


# memory_macro
set memory_macro [EDA::Design::createComponent memory_macro]
$memory_macro addHDLSourceFiles [list \
  "src/memory_macro/memory_macro.sv" \
  "src/memory_macro/asic/memory_model.sv" \
  "src/memory_macro/fpga/xilinx/bram_infered.sv" \
  "src/memory_macro/fpga/xilinx/xpm_wrapper.sv" \
  "src/memory_macro/fpga/xilinx/xpm_dual_wrapper.sv" \
  ]
