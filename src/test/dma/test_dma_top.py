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

NUM_BUSSES = int(params["W_WORKERS"]) + 1


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
        
    async def mock_buses(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            for b in range(NUM_BUSSES):
                self.dut.bus_ready_i[b].value = 1#int(rnd.random() < 0.5)
        
    async def setup_ingress_cfg(self, configs, topology):
        await self._send_topology_cfg(topology)
        
        for stream_id, cfg in configs.items():
            await self._send_stream_cfg(stream_id, cfg)
            
    async def setup_global_cfg(self, bank_limit, bank_header_size, bank_bases):
        await self.ctrl_driver.send_global_config("bank_limit_b", bank_limit)
        await self.ctrl_driver.send_global_config("bank_header_size_b", bank_header_size)
        for bank_idx, base in enumerate(bank_bases):
            await self.ctrl_driver.send_global_config("bank_base", base, bank_idx)   
            
    async def activate_streams(self, configs):
        for stream_id in configs.keys():
            await self._activate_stream(stream_id)     
            
    async def send_egress_cfg(self, stream_id, idx, cfg):
        pass
            
        
    async def _send_stream_cfg(self, stream_id, cfg):
        await self.ctrl_driver.send_ingress_config("start_macro", cfg["start_macro"], stream_id)
        await self.ctrl_driver.send_ingress_config("window_size", 10, stream_id)#cfg["window_size"], stream_id)
        await self.ctrl_driver.send_stream_interval(stream_id, 3)#cfg["interval"])
        
    async def _send_topology_cfg(self, topology):
        for i in range(0, self.m_macros, 2):
            await self.ctrl_driver.send_topology_pair(i, topology)
        
    async def _activate_stream(self, stream_id):
        await self.ctrl_driver.send_ingress_config("stream_en", 1, stream_id)
        
    def _init_signals(self):                
        for bus in range(NUM_BUSSES):
            self.dut.bus_ready_i[bus].value = 0  
    

@cocotb.test()
async def test_dma_top(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    w_workers = int(params["W_WORKERS"])
    
    driver = DMATopDriver(dut)
    
    await driver.reset()
    cocotb.start_soon(driver.mock_buses())
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    for i in range(1):
        configs, topology = config_randomizer.generate_configs(verbose=True)
        
        await driver.setup_ingress_cfg(configs, topology)        
        
        bank_limit = 1024
        bank_header_size = 512
        bank_bases = [0, 1024]
        await driver.setup_global_cfg(bank_limit, bank_header_size, bank_bases)
        
        await driver.activate_streams(configs)
        
        NUM_WINDOWS = 100
        MAX_CYCLES = 3001
        for cycle in range(MAX_CYCLES):
            await RisingEdge(dut.clk_i)
            await ReadOnly()
            
            if dut.ingr_req.value == 1 and dut.ingr_gnt.value == 1:
                #print(f"Cycle {cycle}: Ingress - Addr: {int(dut.ingr_addr[0].value)}, Data: {int(dut.ingr_wdata[0].value)}")
                pass
            
            if dut.egr_req.value == 1 and dut.egr_gnt.value == 1:
                #print(f"Cycle {cycle}: Buffer Pool - Addr: {int(dut.egr_addr[0].value)}, Macro Sel: {int(dut.egr_macro_select[0].value)}")
                pass
            
            for bus in range(NUM_BUSSES):                
                if dut.bus_valid_o[bus].value and dut.bus_ready_i[bus].value:
                    address = int(dut.bus_addr_o[bus].value)
                    wdata = int(dut.bus_wdata_o[bus].value)
                    print(f"Cycle {cycle}: Bus {bus} - Address: {address}, WData: {wdata}")
                    
            if cycle % 1000 == 0:
                print(f"Cycle {cycle} completed.")
    
    
    