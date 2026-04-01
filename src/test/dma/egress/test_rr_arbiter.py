import cocotb
import random as rnd

from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge
from cocotb.clock import Clock


class GoldenModel:
    def __init__(self, n):
        self.n = n
        self.pointer = 0
        
    def step(self, ready_i, req_i):
        ready = [bool(ready_i & (1 << i)) for i in range(self.n)]
        
        if int(req_i) == 0 or not any(ready):
            return None
        
        order = [i % self.n for i in range(self.pointer, self.pointer + self.n)]
        
        grant = next(i for i in order if ready[i])        
        self.pointer = (grant + 1) % self.n

        return grant
    
    
@cocotb.test()
async def test_rr_arbiter(dut):
    n = int(dut.N.value)
    rnd.seed(42)
    golden_model = GoldenModel(n)
    
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    dut.req_i.value = 0
    dut.ready_i.value = 0
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        idle = rnd.randint(0, 4) 
        dut.req_i.value = 0
        dut.ready_i.value = 0
        await ClockCycles(dut.clk_i, idle)

        ready_val = rnd.randint(0, (1 << n) - 1)
        dut.ready_i.value = ready_val
        req_val = 1
        
        dut.req_i.value = req_val
            
        expected = golden_model.step(ready_val, req_val)
        
        await ReadOnly()
        
        actual_gnt = int(dut.gnt_o.value)
        actual_valid = int(dut.valid_o.value)

        if expected is None:
            assert actual_valid == 0, f"Expected valid_o to be 0, got: {actual_valid}"
        else:
            assert actual_valid == 1, f"Expected valid_o to be 1, got: {actual_valid}"
            actual = actual_gnt.bit_length() - 1 if actual_gnt != 0 else None
            assert actual == expected, f"Expected gnt_o to be {expected}, got: {actual}"
            
        await RisingEdge(dut.clk_i)
        