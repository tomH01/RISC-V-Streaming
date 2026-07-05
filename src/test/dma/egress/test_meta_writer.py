import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class MetaWriterDriver:
    def __init__(self, dut):    
        self.dut = dut
        
        self.b_banks = int(params["B_BANKS"])
        
        self._init_signals()
        
        self.current_bank_idx = 0
        
    def _init_signals(self):
        self.dut.meta_valid_i.value = 0
        self.dut.meta_done_o.value = 0
        self.dut.meta_close_bank_i.value = 0
        self.dut.meta_bank_idx_i.value = 0
        self.dut.meta_window_id_i.value = 0
        self.dut.meta_window_size_i.value = 0
        
        for b in range(self.b_banks):
            self.dut.l2_bank_base_i[b].value = 0
        
        self.bus_ready_i = 0
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)   
        
    async def set_bank_bases(self, bank_bases):
        for b in range(len(bank_bases)):
            self.dut.l2_bank_base_i[b].value = bank_bases[b]
        await RisingEdge(self.dut.clk_i)
    
    async def mock_bus(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            self.dut.bus_ready_i.value = int(rnd.random() < 0.5)

    async def send_rnd_meta(self, close_bank=False): 
        if close_bank:
            self.current_bank_idx = (self.current_bank_idx + 1) % self.b_banks
        window_id = rnd.randint(0, 2**int(params["DATA_WIDTH"]) - 1)
        window_size = rnd.randint(0, 2**int(params["DATA_WIDTH"]) - 1)
        
        self.dut.meta_valid_i.value = 1
        self.dut.meta_close_bank_i.value = int(close_bank)
        self.dut.meta_bank_idx_i.value = self.current_bank_idx
        self.dut.meta_window_id_i.value = window_id
        self.dut.meta_window_size_i.value = window_size
        await RisingEdge(self.dut.clk_i)
        self.dut.meta_valid_i.value = 0
        self.dut.meta_close_bank_i.value = 0
        self.dut.meta_bank_idx_i.value = 0
        self.dut.meta_window_id_i.value = 0
        self.dut.meta_window_size_i.value = 0
        

class GoldenModel:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard

        self.b_banks = int(params["B_BANKS"])
        self.data_width_bytes = int(params["DATA_WIDTH"]) // 8
        
        self.bank_counters = [0] * self.b_banks
        self.bank_pointers = [1] * self.b_banks
        self.bank_bases = [0] * self.b_banks
        
        self.fifo_mem = []
        
    async def initialize(self):
        await ReadOnly()
        
        for b in range(self.b_banks):
            self.bank_bases[b] = int(self.dut.l2_bank_base_i[b].value)
        await RisingEdge(self.dut.clk_i)

    async def run(self):
        while True:
            while len(self.fifo_mem) == 0:
                await RisingEdge(self.dut.clk_i)
            
            await RisingEdge(self.dut.clk_i)
            
            pkt = self.fifo_mem.pop(0)
            
            # Write close bank count
            if pkt["close_bank"] == 1:
                closed_bank = (pkt["bank_idx"] - 1) % self.b_banks
                
                
                result = {
                    "bank": closed_bank,
                    "address": self.bank_bases[closed_bank],
                    "wdata": self.bank_counters[closed_bank]
                }
                self.scoreboard.add_expected(result)    
                
                self.bank_counters[closed_bank] = 0
                self.bank_pointers[closed_bank] = 1
                
            # Write window id
            bank_idx = pkt["bank_idx"]
            address = self.bank_bases[bank_idx] + self.bank_pointers[bank_idx] * self.data_width_bytes
            result = {
                "bank": bank_idx,
                "address": address,
                "wdata": pkt["window_id"]
            }
            self.scoreboard.add_expected(result)
            self.bank_pointers[bank_idx] += 1        
            
            # Write window size
            address = self.bank_bases[bank_idx] + self.bank_pointers[bank_idx] * self.data_width_bytes
            result = {
                "bank": bank_idx,
                "address": address,
                "wdata": pkt["window_size"]
            }
            self.scoreboard.add_expected(result)
            self.bank_pointers[bank_idx] += 1
            self.bank_counters[bank_idx] += 1   
            
    async def wait_for_bus(self):
        while True:
            await ReadOnly()
            
            if self.dut.bus_valid_o.value == 1 and self.dut.bus_ready_i.value == 1:
                await RisingEdge(self.dut.clk_i)
                break
            await RisingEdge(self.dut.clk_i)
            
    async def fifo(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()

            if self.dut.meta_valid_i.value == 1 and self.dut.meta_ready_o.value == 1:
                pkt = {
                    "close_bank": int(self.dut.meta_close_bank_i.value),
                    "bank_idx": int(self.dut.meta_bank_idx_i.value),
                    "window_id": int(self.dut.meta_window_id_i.value),
                    "window_size": int(self.dut.meta_window_size_i.value)
                }
                self.fifo_mem.append(pkt)



class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.bus_valid_o.value and self.dut.bus_ready_i.value:
                result = {
                    "bank": int(self.dut.bus_bank_o.value),
                    "address": int(self.dut.bus_addr_o.value),  
                    "wdata": int(self.dut.bus_wdata_o.value),
                }
                
                self.scoreboard.add_actual(result)    
        

class ScoreBoard:
    def __init__(self, dut):
        self.dut = dut
        self.expected_q = Queue()
        self.actual_q = Queue()
        
    def add_expected(self, value):
        self.expected_q.put_nowait(value)
        
    def add_actual(self, value):
        self.actual_q.put_nowait(value)
        
    async def compare(self):
        while True:
            expected = await self.expected_q.get()
            actual = await self.actual_q.get()
            
            assert expected == actual, f"Expected: {expected}, Actual: {actual}"
            
            
    async def run(self):
        cocotb.start_soon(self.compare())
    


@cocotb.test()
async def test_meta_writer_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    scoreboard = ScoreBoard(dut)
    cocotb.start_soon(scoreboard.run())
    
    output_monitor = OutputMonitor(dut, scoreboard)
    cocotb.start_soon(output_monitor.monitor())
    
    golden_model = GoldenModel(dut, scoreboard)
    driver = MetaWriterDriver(dut)
    
    await driver.reset()
    cocotb.start_soon(driver.mock_bus())
    await driver.set_bank_bases([rnd.randint(0, 2**16) - 1 for _ in range(driver.b_banks)])
    
    await golden_model.initialize()
    cocotb.start_soon(golden_model.fifo())
    cocotb.start_soon(golden_model.run())
    await RisingEdge(dut.clk_i)
    
    NUM_WRITES = 10000
    for i in range(NUM_WRITES):
        timeout = 10000
        
        for _ in range(timeout):
            await NextTimeStep()
            if dut.meta_ready_o.value == 1:
                break
            await RisingEdge(dut.clk_i)
        else:
            raise Exception("Timeout waiting for meta_ready_o to be 1")
        
        close_bank = rnd.random() < 0.1 and i > 0
        await driver.send_rnd_meta(close_bank=close_bank)
            
        if close_bank:
            for _ in range(timeout):
                if dut.meta_done_o.value == 1:
                    break
                await RisingEdge(dut.clk_i)
            else:
                raise Exception("Timeout waiting for meta_done_o to be 1")
            
        if i % 1000 == 0:
            print(f"Progress: {i}/{NUM_WRITES}")