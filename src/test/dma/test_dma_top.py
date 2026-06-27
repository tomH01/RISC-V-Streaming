import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from apb_driver import APBDriver
from config_randomizer import ConfigRandomizer
from control_driver import ControlDriver

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class DMATopDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
        self.m_macros = int(params["M_MACROS"])
        
        self.ctrl_driver = ControlDriver(dut)
        
        self._init_signals()
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def setup(self, configs, topology):
        await self.send_topology_cfg(topology)
        
        for stream_id, cfg in configs.items():
            await self.send_stream_cfg(stream_id, cfg)
        
        for stream_id in configs.keys():
            await self.activate_stream(stream_id)
        
        
    async def send_stream_cfg(self, stream_id, cfg):
        await self.ctrl_driver.send_ingress_config("start_macro", cfg["start_macro"], stream_id)
        await self.ctrl_driver.send_ingress_config("window_size", cfg["window_size"], stream_id)
        await self.ctrl_driver.send_stream_interval(stream_id, cfg["interval"])
        
        
    async def send_topology_cfg(self, topology):
        for i in range(0, self.m_macros, 2):
            await self.ctrl_driver.send_topology_pair(i, topology)
            
    async def send_egress_cfg(self, stream_id, idx, cfg):
        pass
        
    async def activate_stream(self, stream_id):
        await self.ctrl_driver.send_ingress_config("stream_en", 1, stream_id)
        
    def _init_signals(self):                
        for w in range(self.w_workers):
            self.dut.bus_ready_i[w].value = 0  
    

@cocotb.test()
async def test_dma_top(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    
    driver = DMATopDriver(dut)
    
    await driver.reset()
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    for i in range(1):
        configs, topology = config_randomizer.generate_configs()
        
        await driver.setup(configs, topology)        
        
        await RisingEdge(dut.clk_i)
        NUM_WINDOWS = 100
        #for j in range(NUM_WINDOWS):
        #    await RisingEdge(dut.clk_i)
    
    
    
    