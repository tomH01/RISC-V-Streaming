import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer

from control_driver import ControlDriver
from base_driver import BaseDriver
from dma_driver import DMADriver

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class TopDriver(BaseDriver):
    def __init__(self, dut):
        self.dut = dut
        
        self.ctrl_driver = ControlDriver(dut, driver_protocol="apb")
        self.dma_driver = DMADriver(dut, self.ctrl_driver)
        
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
    
    driver = TopDriver(dut)
    
    await driver.reset()
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    for i in range(1):
        configs, topology = config_randomizer.generate_configs(verbose=True)
        
        await driver.dma_driver.setup_ingress_cfg(configs, topology)        
        
        bank_base = 0
        await driver.dma_driver.setup_global_cfg(bank_base)
        
        await driver.dma_driver.activate_streams(configs)
        
        NUM_WINDOWS = 100
        MAX_CYCLES = 3001
        for cycle in range(MAX_CYCLES):
            await RisingEdge(dut.clk_i)
            await ReadOnly()
                    
            if cycle % 1000 == 0:
                print(f"Cycle {cycle} completed.")
    
    
    