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

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class TopDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
        self.m_macros = int(params["M_MACROS"])
        
        self.ctrl_driver = ControlDriver(dut)
        
        self._init_signals()
        
    def _init_signals(self):
        self.dut.cpu_valid_i.value = 0
        self.dut.cpu_addr_i.value = 0
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def setup_ingress_cfg(self, configs, topology):
        await self._send_topology_cfg(topology)
        
        for stream_id, cfg in configs.items():
            await self._send_stream_cfg(stream_id, cfg)
            
    async def setup_global_cfg(self, bank_base):
        await self.ctrl_driver.send_global_config("bank_base", bank_base)
        await RisingEdge(self.dut.clk_i)
        await self.ctrl_driver.send_global_config("egress_enable", self.ctrl_driver.get_enable(True))   
            
    async def activate_streams(self, configs):
        for stream_id in configs.keys():
            await self._activate_stream(stream_id)     
            
    async def send_egress_cfg(self, stream_id, idx, cfg):
        pass
            
        
    async def _send_stream_cfg(self, stream_id, cfg):
        await self.ctrl_driver.send_ingress_config("start_macro", cfg["start_macro"], stream_id)
        await self.ctrl_driver.send_ingress_config("window_size", 100, stream_id) #cfg["window_size"], stream_id)
        await self.ctrl_driver.send_stream_interval(stream_id, 1) #cfg["interval"])
        
    async def _send_topology_cfg(self, topology):
        for i in range(0, self.m_macros, 2):
            await self.ctrl_driver.send_topology_pair(i, topology)
        
    async def _activate_stream(self, stream_id):
        await self.ctrl_driver.send_ingress_config("stream_en", 1, stream_id)    

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
        
        await driver.setup_ingress_cfg(configs, topology)        
        
        bank_base = 0
        await driver.setup_global_cfg(bank_base)
        
        await driver.activate_streams(configs)
        
        NUM_WINDOWS = 100
        MAX_CYCLES = 3001
        for cycle in range(MAX_CYCLES):
            await RisingEdge(dut.clk_i)
            await ReadOnly()
                    
            if cycle % 1000 == 0:
                print(f"Cycle {cycle} completed.")
    
    
    