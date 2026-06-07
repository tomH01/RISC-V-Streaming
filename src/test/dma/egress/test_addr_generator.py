import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotb.clock import Clock

from get_param import get_param
from config_randomizer import ConfigRandomizer
from addr_generator_models import Mode, LinearGeneratorModel, StridedGeneratorModel


class AddrGenDriver:
    def __init__(self, dut):
        self.dut = dut

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def set_topology(self, topology):
        for current_m, next_m in topology.items():
            self.dut.next_pointer_i[current_m].value = next_m
    
    async def dispatch_job(self):
        pass
        
        
        
class GoldenModel:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.score_board = score_board
        
        self.topology = None
        
        self.generators = self.get_generators()
        
    def reset(self):
        self.topology = None
    
    async def initialize(self):
        pass
    
    def process_job(self, job, bp_data):
        # TODO: get those somehow
        self.gen_bp_transactions(job)
        self.gen_bus_transactions()
        
    def gen_bp_transactions(self, job):
        window_size = job['window_size']
        config_payload = job['config_payload']
        
        generator = self.generators[job["mode"]]
        generator.initialize(config_payload)
        
        for _ in range(window_size):
            generator.step()
        
    def gen_bus_transactions(self):
        pass
    
    def get_generators(self):
        self.count_width = get_param(self.dut, "COUNT_WIDTH")
        self.stride_width = get_param(self.dut, "STRIDE_WIDTH")
        self.num_axes = get_param(self.dut, "NUM_AXES")
        return {
                Mode.LINEAR: LinearGeneratorModel(),
                Mode.STRIDED: StridedGeneratorModel(self.count_width, self.stride_width, self.num_axes)
        }
        
        
class Scoreboard:
    def __init__(self):
        self.expected_bp_q = Queue()
        self.actual_bp_q = Queue()
        
        self.expected_bus_q = Queue()
        self.actual_bus_q = Queue()
        
    def add_expected_bp(self, value):
        self.expected_bp_q.put_nowait(value)
        
    def add_actual_bp(self, value):
        self.actual_bp_q.put_nowait(value)
        
    async def compare_bp(self):
        while True:
            exp = await self.expected_bp_q.get()
            act = await self.actual_bp_q.get()
        
    def add_expected_bus(self, value):
        self.expected_bus_q.put_nowait(value)
        
    def add_actual_bus(self, value):
        self.actual_bus_q.put_nowait(value)
        
    async def compare_bus(self):
        while True:
            exp = await self.expected_bus_q.get()
            act = await self.actual_bus_q.get()
            
    def clear(self):
        assert self.expected_bp_q.empty(), "Expected bp queue is not empty"
        assert self.actual_bp_q.empty(), "Actual bp queue is not empty"
        
        assert self.expected_bus_q.empty(), "Expected bus queue is not empty"
        assert self.actual_bus_q.empty(), "Actual bus queue is not empty"

        while not self.expected_bp_q.empty():
            self.expected_bp_q.get_nowait()
        while not self.actual_bp_q.empty():
            self.actual_bp_q.get_nowait()

        while not self.expected_bus_q.empty():
            self.expected_bus_q.get_nowait()
        while not self.actual_bus_q.empty():
            self.actual_bus_q.get_nowait()
            
    async def run(self):
        await self.compare_bp() 
        await self.compare_bus()   
        

class BufferPoolMonitor:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.score_board = score_board
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.bp_req_o.value == 1 and self.dut.bp_gnt_i.value == 1:
                actual = {
                    "addr": int(self.dut.bp_addr_o.value),
                    "macro_sel": int(self.dut.bp_macro_sel_o.value)
                }
                self.score_board.add_actual_bp(actual)
            
            
class BusMonitor:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.score_board = score_board
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.bus_valid_o.value == 1 and self.dut.bus_ready_i.value == 1:
                actual = {
                    "addr": int(self.dut.bus_addr_o.value),
                    "wdata": int(self.dut.bus_wdata_o.value)
                }
                self.score_board.add_actual_bus(actual)
                
                

@cocotb.test()
async def test_addr_generator_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    n_streams = get_param(dut, "N_STREAMS")
    m_macros = get_param(dut, "M_MACROS")
    macro_depth = get_param(dut, "MACRO_DEPTH")
    
    driver = AddrGenDriver(dut)
    score_board = Scoreboard()
    golden_model = GoldenModel(dut, score_board)
    bp_monitor = BufferPoolMonitor(dut, score_board)
    bus_monitor = BusMonitor(dut, score_board)
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    for i in range(1):
        print(i)
        
        config_per_stream, topology = config_randomizer.generate_configs()
        
        await driver.set_topology(topology)
        await driver.reset()
        
        score_board.clear()
        
        golden_model.reset()
        #await golden_model.initialize()   
        score_board_task = cocotb.start_soon(score_board.run())
        #golden_model_task = cocotb.start_soon(golden_model.run())   
        bp_monitor_task = cocotb.start_soon(bp_monitor.monitor()) 
        bus_monitor_task = cocotb.start_soon(bus_monitor.monitor())
        
        NUM_TEST_JOBS = 100
        for _ in range(NUM_TEST_JOBS):
            while True:
                if dut.done_o.value == 1:
                    break
                
                
            
        score_board_task.kill()
        #golden_model_task.kill()
        bp_monitor_task.kill()
        bus_monitor_task.kill()
            
            
