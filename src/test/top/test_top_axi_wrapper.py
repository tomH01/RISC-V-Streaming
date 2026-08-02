import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer
from base_driver import BaseDriver
from control_driver import ControlDriver
from dma_driver import DMADriver
from axi_driver import AXIDriver

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class TopAXIWrapperDriver(BaseDriver):
    def __init__(self, dut):
        super().__init__(dut)
        
        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
        self.m_macros = int(params["M_MACROS"])
        
        self.ctrl_driver = ControlDriver(dut, driver_protocol="axi")  
        self.axi_driver = AXIDriver(dut)
        self.dma_driver = DMADriver(dut, self.ctrl_driver, self.axi_driver)

@cocotb.test()
async def test_top_axi_wrapper(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    data_width = int(params["DATA_WIDTH"])
    data_width_b = data_width // 8

    bank_base = 0x4000_0000
    
    driver = TopAXIWrapperDriver(dut)
    
    await driver.reset()
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    for i in range(1):
        configs, topology = config_randomizer.generate_configs(verbose=True)
        
        await driver.dma_driver.setup_ingress_cfg(configs, topology)        
        
        await driver.dma_driver.setup_global_cfg(bank_base)
        
        await driver.dma_driver.activate_streams(configs)
    
    while True:
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if (dut.job_dispatched_o.value == 1):
            break   
    
    await RisingEdge(dut.clk_i)
    ctrl_data = await driver.ctrl_driver.driver.read(0x0800_4000)
    print(f"Control read data: 0x{ctrl_data:08X}")
    
    cpu_done_ptr = bank_base
    agu_done_ptr = [bank_base] * n_streams
    current_job = {
        "stream_id": -1,           
        "size": 0
        }
    
    for i in range(100):
        if current_job["size"] == 0:
            while True:
                await RisingEdge(dut.clk_i)
                await ReadOnly()
                if (dut.job_dispatched_o.value == 1):
                    break
            await RisingEdge(dut.clk_i) 
            dispatch_data = await driver.dma_driver.read_fifo_top()
            stream_id, size = driver.dma_driver.decode_dispatch_data(dispatch_data)
            current_job = {
                "stream_id": stream_id,
                "size": size
            }
            print(f"Dispatch data: Stream ID: {stream_id}, Size: {size}")
        
        if agu_done_ptr[current_job["stream_id"]] > cpu_done_ptr:
            stream_data = await driver.axi_driver.read(cpu_done_ptr)
            current_job["size"] -= data_width_b
            print(f"Addr: 0x{cpu_done_ptr:08X} Data: 0x{stream_data:08X}")
            cpu_done_ptr += data_width_b
        else:
            ptr = await driver.dma_driver.read_agu_done_ptr(current_job["stream_id"])
            agu_done_ptr[current_job["stream_id"]] = ptr
            print(f"AGU done pointer: 0x{ptr:08X}")
    