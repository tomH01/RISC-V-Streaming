import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer
from addr_generator_models import Mode, LinearGeneratorModel, StridedGeneratorModel

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class AddrGenDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.m_macros = int(params["M_MACROS"])
        
        self.bp_data_q = Queue()
        
        self._init_signals()
        

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    def _init_signals(self):
        self.dut.sel_i.value = 0
        
        self.dut.job_assign_valid_i.value = 0
        self.dut.job_assign_stream_id_i.value = 0
        self.dut.job_assign_start_macro_i.value = 0
        self.dut.job_assign_window_size_i.value = 0
        self.dut.job_assign_mode_i.value = 0
        self.dut.job_assign_window_id_i.value = 0
        self.dut.job_assign_payload_i.value = 0
        
        self.dut.job_addr_i.value = 0
        self.dut.job_bank_i.value = 0
        
        for m in range(self.m_macros):
            self.dut.next_pointer_i[m].value = 0
            
        self.dut.bp_gnt_i.value = 0
        self.dut.bp_r_rdata_i.value = 0
        self.dut.bp_r_valid_i.value = 0
        
        self.dut.bus_ready_i.value = 0
        
        
    async def set_topology(self, topology):
        for current_m, next_m in topology.items():
            self.dut.next_pointer_i[current_m].value = next_m
            
    async def start_responders(self):
        cocotb.start_soon(self._bp_responder())
        cocotb.start_soon(self._bus_responder())
        cocotb.start_soon(self._drive_gnt())
            
    async def sim_job(self, job):
        for bp_data in job['bp_data']:
            self.bp_data_q.put_nowait(bp_data)
        await self._dispatch_job(job)
        
        for _ in range(10000):
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.job_done_o.value == 1:
                break
        else: 
            raise Exception("Job did not complete within timeout")
        await RisingEdge(self.dut.clk_i)
    
        
    async def _dispatch_job(self, job):
        self.dut.sel_i.value = 1
        self.dut.job_assign_valid_i.value = 1
        self.dut.job_assign_stream_id_i.value = job['stream_id']
        self.dut.job_assign_start_macro_i.value = job['start_macro']
        self.dut.job_assign_window_size_i.value = job['window_size']
        self.dut.job_assign_mode_i.value = job['mode'].value
        self.dut.job_assign_window_id_i.value = job['window_id']
        self.dut.job_assign_payload_i.value = job['config_payload']
        self.dut.job_addr_i.value = job['addr']
        self.dut.job_bank_i.value = job['bank']
        
        await RisingEdge(self.dut.clk_i)
        
        self.dut.sel_i.value = 0
        self.dut.job_assign_valid_i.value = 0
        
    async def _bp_responder(self):
        next_r_valid = 0
        next_r_data = 0
        
        while True:
            await RisingEdge(self.dut.clk_i)
            
            self.dut.bp_r_valid_i.value = next_r_valid
            self.dut.bp_r_rdata_i.value = next_r_data
            
            await ReadOnly()
            
            if self.dut.bp_req_o.value == 1:
                if not self.bp_data_q.empty():
                    next_r_data = self.bp_data_q.get_nowait()
                    next_r_valid = 1
                else:
                    raise Exception("BP requested data but bp_data_q is empty")
            else:
                next_r_valid = 0
                next_r_data = 0
                
    async def _drive_gnt(self):
        while True:
            await Edge(self.dut.bp_req_o)
            self.dut.bp_gnt_i.value = self.dut.bp_req_o.value

    async def _bus_responder(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            self.dut.bus_ready_i.value = rnd.choice([0, 1])
               
        
class GoldenModel:
    def __init__(self, dut, score_board):
        self.dut = dut
        
        self.macro_depth = int(params["MACRO_DEPTH"])
        self.data_width = int(params["DATA_WIDTH"])
        self.bytes_per_word = self.data_width // 8
        
        self.score_board = score_board
        
        self.topology = {}
        
        self.generators = self.get_generators()
    
    def process_job(self, job):
        self.gen_bp_transactions(job)
        self.gen_bus_transactions(job)
        
    def gen_bp_data(self, window_size):
        return [int(rnd.getrandbits(self.data_width)) for _ in range(window_size)]
        
    def gen_bp_transactions(self, job):
        window_size = job['window_size']
        config_payload = job['config_payload']
        
        generator = self.generators[job["mode"]]
        generator.initialize(config_payload)
        
        macro_lut = self._get_macro_lut(job['start_macro'])
        
        for _ in range(window_size):
            win_addr = generator.step()
                        
            expected = {
                    "addr": (win_addr % self.macro_depth) * self.bytes_per_word,
                    "macro_sel": macro_lut[win_addr // self.macro_depth]
            }
            self.score_board.add_expected_bp(expected)
           
    def gen_bus_transactions(self, job):
        addr = job['addr']
        
        for wdata in job['bp_data']:
            expected = {
                    "bank": job['bank'],
                    "addr": addr,
                    "wdata": wdata
            }
            self.score_board.add_expected_bus(expected)
            
            addr += self.bytes_per_word
        
    def get_generators(self):
        self.count_width = int(params["COUNT_WIDTH"])
        self.stride_width = int(params["STRIDE_WIDTH"])
        self.num_axes = int(params["NUM_AXES"])
        return {
                Mode.LINEAR: LinearGeneratorModel(),
                Mode.STRIDED: StridedGeneratorModel(self.count_width, self.stride_width, self.num_axes)
        }
        
    def _get_macro_lut(self, start_macro):
        macro_lut = [start_macro]
        next_macro = self.topology[start_macro]
        
        while next_macro != start_macro:
            macro_lut.append(next_macro)
            next_macro = self.topology[next_macro]
            
        return macro_lut

        
class Scoreboard:
    def __init__(self, dut):
        self.dut = dut
        self.expected_bp_q = Queue()
        self.actual_bp_q = Queue()
        
        self.expected_bus_q = Queue()
        self.actual_bus_q = Queue()
        
        self.counter = 0
        
    def add_expected_bp(self, value):
        self.expected_bp_q.put_nowait(value)
        
    def add_actual_bp(self, value):
        self.actual_bp_q.put_nowait(value)
        
    async def compare_bp(self):
        while True:
            exp = await self.expected_bp_q.get()
            act = await self.actual_bp_q.get()
            
            if exp != act:
                await RisingEdge(self.dut.clk_i)
            
            self.counter += 1
            
            assert exp["addr"] == act["addr"], f"{self.counter}: Expected BP addr {exp['addr']} but got {act['addr']}"
            assert exp["macro_sel"] == act["macro_sel"], f"{self.counter}: Expected BP macro_sel {exp['macro_sel']} but got {act['macro_sel']}"
        
    def add_expected_bus(self, value):
        self.expected_bus_q.put_nowait(value)
        
    def add_actual_bus(self, value):
        self.actual_bus_q.put_nowait(value)
        
    async def compare_bus(self):
        while True:
            exp = await self.expected_bus_q.get()
            act = await self.actual_bus_q.get()
            
            assert exp["bank"] == act["bank"], f"Expected bus bank {exp['bank']} but got {act['bank']}"
            assert exp["addr"] == act["addr"], f"Expected bus addr {exp['addr']} but got {act['addr']}"
            assert exp["wdata"] == act["wdata"], f"Expected bus wdata {exp['wdata']} but got {act['wdata']}"
            
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
        cocotb.start_soon(self.compare_bp()) 
        cocotb.start_soon(self.compare_bus())   
        

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
                    "bank": int(self.dut.bus_bank_o.value),
                    "addr": int(self.dut.bus_addr_o.value),
                    "wdata": int(self.dut.bus_wdata_o.value)
                }
                self.score_board.add_actual_bus(actual)
                

@cocotb.test()
async def test_addr_generator_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])

    driver = AddrGenDriver(dut)
    await driver.start_responders()
    score_board = Scoreboard(dut)
    golden_model = GoldenModel(dut, score_board)
    bp_monitor = BufferPoolMonitor(dut, score_board)
    bus_monitor = BusMonitor(dut, score_board)
    
    config_randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)

    for i in range(10):
        config_per_stream, topology = config_randomizer.generate_configs()
        
        await driver.set_topology(topology)
        await driver.reset()
        score_board.clear()
        
        golden_model.topology = topology        
          
        score_board_task = cocotb.start_soon(score_board.run()) 
        bp_monitor_task = cocotb.start_soon(bp_monitor.monitor()) 
        bus_monitor_task = cocotb.start_soon(bus_monitor.monitor())
        
        NUM_TEST_JOBS = 100
        for j in range(NUM_TEST_JOBS):
            print(f"{i}: Job {j}")
            stream_id = rnd.randrange(n_streams)
            stream_cfg = config_per_stream[stream_id]
            mode = rnd.choice(list(Mode))
            window_size = stream_cfg['window_size']
            generator = golden_model.generators[mode]
            payload = generator.generate_payload(window_size)
            
            job = {
                "stream_id": stream_id,
                "start_macro": rnd.choice(list(stream_cfg['topology'])),
                "window_size": window_size,
                "mode": mode,
                "window_id": 0,
                "config_payload": payload,
                "addr": 0,#rnd.randint(0, 2**10),
                "bank": 0,
                "bp_data": golden_model.gen_bp_data(window_size)
            }           
            
            golden_model.process_job(job)
            await driver.sim_job(job)
                
        await ClockCycles(dut.clk_i, 2)
        score_board.clear()
        score_board_task.kill()
        bp_monitor_task.kill()
        bus_monitor_task.kill()
