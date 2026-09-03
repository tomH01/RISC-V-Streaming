import os

import cocotb
import random as rnd
import numpy as np
import math

from pathlib import Path
from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer

from addr_generator_models import Mode

from control_driver import ControlDriver
from base_driver import BaseDriver
from dma_driver import DMABlockWiseDriver

from data_drivers import OBIDriver
from sensor_set import SensorSet
from utils.python.cocotb import get_design_parameters
from cpu_state import CPUOp

params = get_design_parameters()    


class TopDriver(BaseDriver):
    def __init__(self, dut, sensor_set, header_size_b):
        self.dut = dut
        self.sensor_set = sensor_set
        
        self.ctrl_driver = ControlDriver(dut, driver_protocol="apb")
        self.data_driver = OBIDriver(dut)
        self.dma_driver = DMABlockWiseDriver(dut, self.ctrl_driver, self.data_driver, sensor_set, header_size_b)
        
        self._init_signals()
        
    def _init_signals(self):
        self.dut.data_req_i.value = 0
        self.dut.data_addr_i.value = 0  

@cocotb.test()
async def test_dma_top(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    w_workers = int(params["W_WORKERS"])
    data_width = int(params["DATA_WIDTH"])
    b_banks = int(params["B_BANKS"])
    bank_depth = int(params["BANK_DEPTH"])
    data_width_b = data_width // 8
    
    sensor_set = SensorSet(n_streams, m_macros, macro_depth)
    sensor_set.import_streams("/local/hageltom/teda/bottles/risc-v-streaming/src/test/use_case/w223_l2.csv")
     
    header_size_b = 128
     
    driver = TopDriver(dut, sensor_set, header_size_b)
    ctrl_driver = driver.ctrl_driver
    data_driver = driver.data_driver
    dma_driver = driver.dma_driver
    
    await driver.reset()
    
    configs, topology = sensor_set.generate_configs(verbose=True)
    
    await dma_driver.setup_ingress_cfg(configs, topology)        
    await dma_driver.setup_global_cfg(bank_base=0)
    
    for stream in sensor_set.streams:
        stream.set_fine_tiling_config()
        await dma_driver.send_egress_cfg(
            stream_id=stream.id, 
            counts=stream.counts,
            strides=stream.strides,
            mode=Mode.STRIDED,
            window_id=0
        )
        
    MAX_CYCLES = 3500000
    for cycle in range(MAX_CYCLES):
        dma_driver.cycle = cycle
        
        if cycle % 100000 == 0:
            print(f"Cycle {cycle}")
        
        await ReadOnly()
        
        is_stalled = dut.data_req_i.value == 1 and dut.data_gnt_o.value == 0

        dma_driver.update_bank_queue()
        
        dma_driver.handle_read_response()
        
        dma_driver.get_next_state()

        await RisingEdge(dut.clk_i)
        
        if is_stalled:
            continue
        
        data_driver.clear_bus()
        
        await dma_driver.issue_request(cycle)   
        
    await dma_driver.toggle_dma_enable(False)
    print(await ctrl_driver.fetch_all_perf_counters())         
            