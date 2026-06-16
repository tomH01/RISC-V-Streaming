import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

# from config_randomizer import ConfigRandomizer

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class DMATopDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
        
        self._init_signals()
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    def _init_signals(self):
        for n in range(self.n_streams):
            self.dut.stream_data_i[n].value = 0
            self.dut.stream_valid_i[n].value = 0
            self.dut.stream_ready_o[n].value = 0
        
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 0
        self.dut.paddr_i.value = 0
        self.dut.psel_i.value = 0
        self.dut.pwdata_i.value = 0
        
        for w in range(self.w_workers):
            self.dut.bus_ready_i[w].value = 0     
        

@cocotb.test()
async def test_dma_top(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    
    driver = DMATopDriver(dut)
    
    await driver.reset()
    
    await ClockCycles(dut.clk_i, 10)
    