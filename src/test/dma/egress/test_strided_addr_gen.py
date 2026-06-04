import random as rnd

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from get_param import get_param
from strided_generator_model import StridedGeneratorModel


class StridedAddrGenDriver:
    def __init__(self, dut, count_width, stride_width, num_axes):
        self.dut = dut
        self.dut.job_start_i.value = 0
        self.dut.req_i.value = 0
        self.dut.base_addr_i.value = 0
        self.dut.payload_i.value = 0
        
        self.count_width = count_width
        self.stride_width = stride_width
        self.num_axes = num_axes

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        
    async def initialize(self, base_addr, payload):
        self.dut.req_i.value = 0
        self.dut.base_addr_i.value = base_addr
        self.dut.payload_i.value = payload
        await RisingEdge(self.dut.clk_i)
        self.dut.job_start_i.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.job_start_i.value = 0
        
        
@cocotb.test()
async def test_strided_addr_gen(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    count_width = get_param(dut, "COUNT_WIDTH")
    stride_width = get_param(dut, "STRIDE_WIDTH")
    num_axes = get_param(dut, "NUM_AXES")
    
    driver = StridedAddrGenDriver(dut, count_width, stride_width, num_axes)
    await driver.reset()
    
    NUM_JOBS = 10
    for _ in range(NUM_JOBS):
        await RisingEdge(dut.clk_i)        
        golden_model = StridedGeneratorModel(count_width, stride_width, num_axes)
        
        base_addr = rnd.randint(0, 2**16)
        strides = [rnd.randint(1, 2**driver.stride_width - 1) for _ in range(driver.num_axes)]
        counts = [rnd.randint(1, 2**driver.count_width - 1) for _ in range(driver.num_axes)]
        payload = golden_model.pack_payload(strides, counts)
        
        golden_model.initialize(payload, base_addr)
        await driver.initialize(base_addr, payload)
        
        await RisingEdge(dut.clk_i)
        
        window_size = rnd.randint(0, 2**10)
        
        transferred = 0
        while transferred < window_size:
            await RisingEdge(dut.clk_i)
            driver.dut.req_i.value = 0
            
            if rnd.random() < 0.2:
                driver.dut.req_i.value = 1   
            
                await ReadOnly()
                golden_addr = golden_model.step()           
                dut_addr = int(driver.dut.addr_o.value)

                assert dut_addr == golden_addr, f"Expected {golden_addr}, got {dut_addr}"
                transferred += 1
                