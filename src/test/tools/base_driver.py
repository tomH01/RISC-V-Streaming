import abc

import cocotb
from cocotb.triggers import RisingEdge


class BaseDriver(abc.ABC):
    def __init__(self, dut):
        self.dut = dut
        
    def _init_signals(self):
        pass
    
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
