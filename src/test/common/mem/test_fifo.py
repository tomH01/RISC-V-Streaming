import os

import cocotb
import random as rd

from collections import deque

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb_coverage.coverage import CoverPoint, CoverCross, coverage_db

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


@CoverPoint("fifo.push",
            xf=lambda push, pop, empty, full: push,
            bins=[0, 1])
@CoverPoint("fifo.pop",
            xf=lambda push, pop, empty, full: pop,
            bins=[0, 1])
@CoverPoint("fifo.empty",
            xf=lambda push, pop, empty, full: empty,
            bins=[0, 1])
@CoverPoint("fifo.full",
            xf=lambda push, pop, empty, full: full,
            bins=[0, 1])
@CoverCross("fifo.push_pop_cross",
            items=["fifo.push", "fifo.pop"])
@CoverCross("fifo.empty_full_cross",
            items=["fifo.empty", "fifo.full"])
def cover_fifo(push, pop, empty, full):
    pass


class FIFOScoreboard:
    def __init__(self, depth):
        self.depth = depth
        self.model = deque()
        
    def push(self, value):
        if len(self.model) < self.depth:
            self.model.append(value)
        else:
            raise AssertionError("Model overflow.")
    
    def pop(self):
        if len(self.model) > 0:
            return self.model.popleft()
        else:
            raise AssertionError("Model underflow.")
        
    def is_empty(self):
        return len(self.model) == 0
    
    def is_full(self):
        return len(self.model) == self.depth
    
    def peek(self):
        if self.is_empty():
            return None
        return self.model[0]
    
    
async def fifo_driver(dut, data_width):
    while True:
        push = rd.choice([0, 1])
        pop = rd.choice([0, 1])
        data = rd.getrandbits(data_width)
        
        dut.push_i.value = push
        dut.pop_i.value = pop
        dut.data_i.value = data
        
        await RisingEdge(dut.clk_i)
        
        
async def fifo_monitor(dut, scoreboard):
    was_pop = False
    expected_data = None
    
    while True:
        await ReadOnly()
        
        push = int(dut.push_i.value)
        pop = int(dut.pop_i.value)
        empty = int(dut.empty_o.value)
        full = int(dut.full_o.value)
        
        cover_fifo(push, pop, empty, full)
        
        assert empty == scoreboard.is_empty(), f"Empty signal mismatch: Expected {scoreboard.is_empty()}, got {empty}"
        assert full == scoreboard.is_full(), f"Full signal mismatch: Expected {scoreboard.is_full()}, got {full}"

        if was_pop:
            dout = int(dut.data_o.value)
            assert dut.data_o.value == expected_data, f"Data mismatch: Expected {expected_data}, got {dut.data_o.value}"
            was_pop = False

        if push and not full:
            scoreboard.push(int(dut.data_i.value))
            
        if pop and not empty:
            expected_data = scoreboard.pop()
            was_pop = True
            
        await RisingEdge(dut.clk_i)
   
    
@cocotb.test()
async def test_fifo_crv(dut):
    DEPTH = int(params["DEPTH"])
    DATA_WIDTH = int(params["DATA_WIDTH"])

    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    dut.rst_ni.value = 0
    dut.push_i.value = 0
    dut.pop_i.value = 0
    dut.data_i.value = 0
    
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    
    dut.rst_ni.value = 1  
      
    await RisingEdge(dut.clk_i)
    
    scoreboard = FIFOScoreboard(DEPTH)
    
    driver_task = cocotb.start_soon(fifo_driver(dut, DATA_WIDTH))
    monitor_task = cocotb.start_soon(fifo_monitor(dut, scoreboard))
    
    NUM_CYCLES = 100000
    for _ in range(NUM_CYCLES):
        await RisingEdge(dut.clk_i)

    coverage_db.report_coverage(dut._log.info, bins=True)
    
    driver_task.kill()
    monitor_task.kill()
    