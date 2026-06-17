import cocotb
import random as rnd
import math

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

# from config_randomizer import ConfigRandomizer

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class StreamGeneratorDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        
        self._init_signals()
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    def _init_signals(self):
        for n in range(self.n_streams):
            self.dut.stream_ready_i[n].value = 0
            self.dut.stream_en_i[n].value = 0
            self.dut.stream_interval_i[n].value = 0
            
    async def set_stream_intervals(self, stream_id, interval):
        self.dut.stream_interval_i[stream_id].value = interval
        self.dut.stream_en_i[stream_id].value = 1
        
    async def sim_ready(self, stream_id):
        while True:
            await RisingEdge(self.dut.clk_i)
            self.dut.stream_ready_i[stream_id].value = rnd.choice([0, 1])

class GoldenModel:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.score_board = score_board
        
        self.n_streams = int(params["N_STREAMS"])

        stream_offset_step = 1 <<  int(params["STREAM_OFFSET_WIDTH"])
        self.state = [{
            "data_counter": n * stream_offset_step,
            "drop_counter": 0,
            "has_valid_word": False
        } for n in range(self.n_streams)]
            
    async def run(self, stream_id, interval):
        state = self.state[stream_id]
        
        interval_count = 0
        
        while True:      
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
                
            if self.dut.stream_en_i[stream_id].value == 0:
                state["has_valid_word"] = False
                interval_count = 0
                continue
            
            consumed_this_cycle = False
            
            if state["has_valid_word"] and self.dut.stream_ready_i[stream_id].value == 1:
                self.score_board.add_expected(stream_id, state["data_counter"])
                state["has_valid_word"] = False
                consumed_this_cycle = True
                
                state["data_counter"] += 1
                
            if interval_count >= interval - 1:
                interval_count = 0
                
                if state["has_valid_word"] and not consumed_this_cycle:
                    state["drop_counter"] += 1
                    state["data_counter"] += 1
                
                state["has_valid_word"] = True
            
            else:
                interval_count += 1   
    
    
class OutputMonitor:
    def __init__(self, dut, score_board, stream_id):
        self.dut = dut
        self.score_board = score_board
        
        self.stream_id = stream_id
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.stream_valid_o[self.stream_id].value == 1 \
            and self.dut.stream_ready_i[self.stream_id].value == 1:  
                actual_value = int(self.dut.stream_data_o[self.stream_id].value)              
                self.score_board.add_actual(self.stream_id, actual_value)
        
        
class Scoreboard:
    def __init__(self, dut):
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        
        self.expected_q = [Queue() for _ in range(self.n_streams)]
        self.actual_q = [Queue() for _ in range(self.n_streams)]

    def add_expected(self, stream_id, value):
        self.expected_q[stream_id].put_nowait(value)
        
    def add_actual(self, stream_id, value):
        self.actual_q[stream_id].put_nowait(value)
        
    async def compare(self, stream_id):
        while True:
            exp = await self.expected_q[stream_id].get()
            act = await self.actual_q[stream_id].get()
            
            if exp != act:
                await RisingEdge(self.dut.clk_i)
                
            assert exp == act, f"Stream {stream_id}: Expected {exp}, got {act}"
                    
    async def run(self):
        for n in range(self.n_streams):
            cocotb.start_soon(self.compare(n))
            
    async def wait_for_empty(self):
        for n in range(self.n_streams):
            while not self.expected_q[n].empty() or not self.actual_q[n].empty():
                await RisingEdge(self.dut.clk_i)


@cocotb.test()
async def test_stream_generator(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    n_streams = int(params["N_STREAMS"])
    
    driver = StreamGeneratorDriver(dut)
    score_board = Scoreboard(dut)
    await score_board.run()
    golden_model = GoldenModel(dut, score_board)
    
    intervals = [rnd.randint(1, 10) for _ in range(n_streams)]

    for n in range(n_streams):
        cocotb.start_soon(driver.sim_ready(n))
        cocotb.start_soon(golden_model.run(n, intervals[n]))
        cocotb.start_soon(OutputMonitor(dut, score_board, n).monitor())

    await driver.reset()

    for n in range(n_streams):
        await driver.set_stream_intervals(n, intervals[n])
        
    
    NUM_CYCLES = 100000
    for i in range(NUM_CYCLES):
        await RisingEdge(dut.clk_i)
        if i % 1000 == 0:
            print(f"Cycle {i}")
        
    await score_board.wait_for_empty()
        