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


class L2SubsystemDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.dma_managers = int(params["W_WORKERS"])
        
        self._init_signals()

    def _init_signals(self):
        for d in range(self.dma_managers):
            self.dut.dma_valid_i[d].value = 0
            self.dut.dma_addr_i[d].value = 0
            self.dut.dma_wdata_i[d].value = 0
            
        self.dut.cpu_valid_i.value = 0
        self.dut.cpu_addr_i.value = 0
        
        self.dut.meta_gnt_i.value = 0
        self.dut.meta_r_rdata_i.value = 0
        self.dut.meta_r_valid_i.value = 0

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def dma_write(self, manager_id, addr, data):
        self.dut.dma_valid_i[manager_id].value = 1
        self.dut.dma_addr_i[manager_id].value = addr
        self.dut.dma_wdata_i[manager_id].value = data

    async def cpu_read(self, addr):
        self.dut.cpu_valid_i.value = 1
        self.dut.cpu_addr_i.value = addr

@cocotb.test()
async def test_l2_subsystem_simple(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    dma_managers = int(params["W_WORKERS"])
    
    driver = L2SubsystemDriver(dut)
    await driver.reset()
    for w in range(dma_managers):
        await driver.dma_write(w, 0x1000 + w * 4, w + 1)
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
        