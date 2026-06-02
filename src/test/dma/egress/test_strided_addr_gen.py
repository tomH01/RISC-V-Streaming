import random as rnd

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from get_param import get_param


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
        
        
    def pack_payload(self, strides, counts):
        payload = 0
        axis_width = self.stride_width + self.count_width
        
        for i in range(self.num_axes):
            axis_bits = (strides[i] << self.count_width) | counts[i]
            payload |= axis_bits << (i * axis_width)
        
        return payload
    
    def unpack_payload(self, payload):
        strides = []
        counts = []
        
        stride_mask = (1 << self.stride_width) - 1
        count_mask = (1 << self.count_width) - 1
        axis_width = self.stride_width + self.count_width
        
        for i in range(self.num_axes):
            shifted_payload = payload >> (i * axis_width)
            count = shifted_payload & count_mask
            stride = (shifted_payload >> self.count_width) & stride_mask
            
            strides.append(stride)
            counts.append(count)
        
        return strides, counts
            
        
class GoldenModel:
    def __init__(self, base_addr, payload, driver):
        self.base_addr = base_addr
        self.payload = payload
        self.driver = driver

        self.current_addr = base_addr
        
        strides, counts = self.driver.unpack_payload(payload)
        self.strides = strides
        self.counts = counts
        self.counters = [0 for _ in range(self.driver.num_axes)]      
    
    def step(self):
        out_addr = self.current_addr
        
        for i in range(self.driver.num_axes):
            self.counters[i] += 1
            
            if self.counters[i] < self.counts[i]:
                break
            else:
                self.counters[i] = 0
    
        next_addr = self.base_addr
        for i in range(self.driver.num_axes):
            next_addr += self.counters[i] * self.strides[i]
            
        self.current_addr = next_addr
        return out_addr    
        
        
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
        
        strides = [rnd.randint(1, 2**driver.stride_width - 1) for _ in range(driver.num_axes)]
        counts = [rnd.randint(1, 2**driver.count_width - 1) for _ in range(driver.num_axes)]
        
        base_addr = rnd.randint(0, 2**16)
        payload = driver.pack_payload(strides, counts)
        await driver.initialize(base_addr, payload)
        
        golden = GoldenModel(base_addr, payload, driver)
        
        await RisingEdge(dut.clk_i)
        
        window_size = rnd.randint(0, 2**10)
        
        transferred = 0
        while transferred < window_size:
            await RisingEdge(dut.clk_i)
            driver.dut.req_i.value = 0
            
            if rnd.random() < 0.2:
                driver.dut.req_i.value = 1   
            
                await ReadOnly()
                golden_addr = golden.step()           
                dut_addr = int(driver.dut.addr_o.value)

                assert dut_addr == golden_addr, f"Expected {golden_addr}, got {dut_addr}"
                transferred += 1
                