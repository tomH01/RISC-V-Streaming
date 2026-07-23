import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotb.clock import Clock

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


class L2AllocatorDriver:
    def __init__(self, dut):   
        self.dut = dut
        
        self.b_banks = int(params["B_BANKS"])
        self.w_workers = int(params["W_WORKERS"])
        self.job_length = self._get_job_length()
        
        self._init_signals()
        
    def _init_signals(self):
        self.dut.stream_id_i.value = 0
        self.dut.start_macro_i.value = 0
        self.dut.window_size_i.value = 0
        self.dut.mode_i.value = 0
        self.dut.payload_i.value = 0
        self.dut.job_valid_i.value = 0        

        self.dut.enable_i.value = 0
        self.dut.l2_bank_base_i.value = 0
        
        self.dut.worker_done_i.value = 0
        
        self.dut.dispatch_ready_i.value = 1
        self.dut.cpu_done_ptr_i.value = 0

    async def reset(self):
        self.dut.job_valid_i.value = 0
        self.dut.worker_done_i.value = 0
        self.dut.cpu_done_ptr_i.value = 0
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)   
        
    async def initialize(self, bank_base):
        self.dut.l2_bank_base_i.value = bank_base
        self.dut.cpu_done_ptr_i.value = bank_base
        
        await RisingEdge(self.dut.clk_i)
        self.dut.enable_i.value = 1
        
    async def set_job(self, window_size):        
        payload_len = len(self.dut.payload_i)
        mode_len = len(self.dut.mode_i)
        window_size_len = len(self.dut.window_size_i)
        start_macro_len = len(self.dut.start_macro_i)
        stream_id_len = len(self.dut.stream_id_i)
        theo_len = payload_len + mode_len + window_size_len + start_macro_len + stream_id_len
        
        offset = payload_len + mode_len
        packed_job = self._create_rnd_job(offset, window_size, window_size_len)
        low_bit = 0
        
        self.dut.job_valid_i.value = 1
        
        self.dut.payload_i.value = (packed_job >> low_bit) & ((1 << payload_len) - 1)
        low_bit += payload_len
        
        self.dut.mode_i.value = (packed_job >> low_bit) & ((1 << mode_len) - 1)
        low_bit += mode_len
        
        self.dut.window_size_i.value = int((packed_job >> low_bit) & ((1 << window_size_len) - 1))
        low_bit += window_size_len
        
        self.dut.start_macro_i.value = int((packed_job >> low_bit) & ((1 << start_macro_len) - 1))
        low_bit += start_macro_len
        
        self.dut.stream_id_i.value = int((packed_job >> low_bit) & ((1 << stream_id_len) - 1))
        return packed_job
    
    async def set_done_vector(self, busy_workers):
        busy_indices = [i for i, busy in enumerate(busy_workers) if busy]
        
        if not busy_indices:
            self.dut.worker_done_i.value = 0
            return
        
        n_busy = len(busy_indices)
        
        k_options = list(range(1, n_busy + 1))
        weights = [1.0 / (2**k) for k in k_options]
        
        num_dones = rnd.choices(k_options, weights=weights, k=1)[0]
        
        ones_indices = rnd.sample(busy_indices, num_dones)
        self.dut.worker_done_i.value = sum(1 << i for i in ones_indices)

    def _get_job_length(self):
        stream_id_len = len(self.dut.stream_id_i)
        start_macro_len = len(self.dut.start_macro_i)
        window_size_len = len(self.dut.window_size_i)
        mode_len = len(self.dut.mode_i) 
        payload_len = len(self.dut.payload_i)
        return stream_id_len + start_macro_len + window_size_len + mode_len + payload_len
        
    def _create_rnd_job(self, offset, window_size, window_size_len):
        clean_mask = ~(((1 << window_size_len) - 1) << offset)
        packed_job = int(rnd.getrandbits(self._get_job_length()))
        packed_job &= clean_mask
        packed_job |= (window_size << offset)
        return packed_job
    
    
class GoldenModel:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.scoreboard = score_board
        
        self.data_width = int(params["DATA_WIDTH"])
        self.b_banks = int(params["B_BANKS"])
        self.bank_depth = int(params["BANK_DEPTH"])
        self.w_workers = int(params["W_WORKERS"])
        self.sram_size_b = self.b_banks * self.bank_depth * self.data_width // 8
        
        self.bank_base = 0
        
        self.state = {
            'dispatch_ptr': 0,
            'busy_workers': [False] * self.w_workers,
        }
        
    def reset(self):
        self.state['dispatch_ptr'] = 0
        self.state['busy_workers'] = [False] * self.w_workers

    async def run(self):        
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.rst_ni.value == 0:
                self.reset()
                await ClockCycles(self.dut.clk_i, 2)
                continue
            
            if self.dut.enable_i.value == 0:
                self.bank_base = int(self.dut.l2_bank_base_i.value)
                self.state['dispatch_ptr'] = int(self.dut.l2_bank_base_i.value)
                continue            
            
            window_size = int(self.dut.window_size_i.value)
            window_size_b = window_size * self.data_width // 8
            
            job_valid = int(self.dut.job_valid_i.value)
            enable = int(self.dut.enable_i.value)
            dispatch_ready = int(self.dut.dispatch_ready_i.value)
            occupied_space = (self.state['dispatch_ptr'] - int(self.dut.cpu_done_ptr_i.value)) % self.sram_size_b
            has_space_available = (occupied_space + window_size_b) <= self.sram_size_b

            worker_idx = self.get_idle_worker()
            
            # Dispatch
            if job_valid and enable and worker_idx is not None and has_space_available and dispatch_ready:
                job = {
                    'job_wid': worker_idx,
                    'job_addr': self.state['dispatch_ptr'],
                    'stream_id': int(self.dut.stream_id_i.value),
                    'start_macro': int(self.dut.start_macro_i.value),
                    'window_size': window_size,
                    'mode': int(self.dut.mode_i.value),
                    'payload': int(self.dut.payload_i.value)
                }
                self.scoreboard.add_expected_job(job)
                self.state['dispatch_ptr'] = self.bank_base + (self.state['dispatch_ptr'] - self.bank_base + window_size_b) % self.sram_size_b  
                
                meta = self._get_meta_data(int(self.dut.stream_id_i.value), window_size)
                self.scoreboard.add_expected_meta(meta)
                
                self.state['busy_workers'][worker_idx] = True
                
            self.update_busy_workers(int(self.dut.worker_done_i.value))
    
    def get_idle_worker(self):
        return next((i for i, busy in enumerate(self.state['busy_workers']) if not busy), None)
    
    def update_busy_workers(self, done_vector):
        for i in range(len(self.state['busy_workers'])):
            if done_vector & (1 << i):
                self.state['busy_workers'][i] = False
                
    def _get_meta_data(self, stream_id, window_size):
        return {
            "dispatch_data": (stream_id << 27) | window_size,
            "dispatch_worker_id": self.get_idle_worker()
        }
            
        
class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.job_valid_o.value:
                job = {
                    'job_wid': int(self.dut.job_wid_o.value),
                    'job_addr': int(self.dut.job_addr_o.value),
                    'stream_id': int(self.dut.stream_id_o.value),
                    'start_macro': int(self.dut.start_macro_o.value),
                    'window_size': int(self.dut.window_size_o.value),
                    'mode': int(self.dut.mode_o.value),
                    'payload': int(self.dut.payload_o.value)
                }
                self.scoreboard.add_actual_job(job)   
                
            if self.dut.dispatch_valid_o.value:
                meta = {
                    "dispatch_data": int(self.dut.dispatch_data_o.value),
                    "dispatch_worker_id": int(self.dut.dispatch_worker_id_o.value)
                }
                self.scoreboard.add_actual_meta(meta)      
            
            
class Scoreboard:
    def __init__(self, dut):
        self.dut = dut
        self.expected_job_q = Queue()
        self.actual_job_q = Queue()
        self.expected_meta_q = Queue()
        self.actual_meta_q = Queue()
        self.added = 0

    def add_expected_job(self, value):
        self.expected_job_q.put_nowait(value)
        
    def add_actual_job(self, value):
        self.actual_job_q.put_nowait(value)
        self.added += 1
        
    def add_expected_meta(self, value):
        self.expected_meta_q.put_nowait(value)
        
    def add_actual_meta(self, value):
        self.actual_meta_q.put_nowait(value)
        
    async def compare_jobs(self):
        while True:
            exp = await self.expected_job_q.get()
            act = await self.actual_job_q.get()
            
            if exp != act:
                await RisingEdge(self.dut.clk_i)
                        
            assert exp['job_wid'] == act['job_wid'], f"Expected worker ID {exp['job_wid']}, got {act['job_wid']}"
            assert exp['job_addr'] == act['job_addr'], f"Expected job address {exp['job_addr']}, got {act['job_addr']}"
            assert exp['stream_id'] == act['stream_id'], f"Expected stream ID {exp['stream_id']}, got {act['stream_id']}"
            assert exp['start_macro'] == act['start_macro'], f"Expected start macro {exp['start_macro']}, got {act['start_macro']}"
            assert exp['window_size'] == act['window_size'], f"Expected window size {exp['window_size']}, got {act['window_size']}"
            assert exp['mode'] == act['mode'], f"Expected mode {exp['mode']}, got {act['mode']}"
            assert exp['payload'] == act['payload'], f"Expected payload {exp['payload']}, got {act['payload']}"

    async def compare_meta(self):
        while True:
            exp = await self.expected_meta_q.get()
            act = await self.actual_meta_q.get()
            
            if exp != act:
                await RisingEdge(self.dut.clk_i)
            
            assert exp["dispatch_data"] == act["dispatch_data"], f"Expected dispatch data {exp['dispatch_data']}, got {act['dispatch_data']}"
    
    def clear(self):
        while not self.expected_job_q.empty():
            self.expected_job_q.get_nowait()
        while not self.actual_job_q.empty():
            self.actual_job_q.get_nowait()
        while not self.expected_meta_q.empty():
            self.expected_meta_q.get_nowait()
        while not self.actual_meta_q.empty():
            self.actual_meta_q.get_nowait()
            
    async def run(self):
        cocotb.start_soon(self.compare_jobs())
        cocotb.start_soon(self.compare_meta())

@cocotb.test()
async def test_l2_allocator_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    b_banks = int(params["B_BANKS"])
    w_workers = int(params["W_WORKERS"])
    
    for i in range(100):
        print(i)
        bank_base = rnd.randint(0, 1024)
        driver = L2AllocatorDriver(dut)
        await driver.reset()
        
        score_board = Scoreboard(dut)
        golden_model = GoldenModel(dut, score_board)
        output_monitor = OutputMonitor(dut, score_board) 
        
        score_board_task = cocotb.start_soon(score_board.run())
        golden_model_task = cocotb.start_soon(golden_model.run())   
        output_monitor_task = cocotb.start_soon(output_monitor.monitor()) 
        
        await RisingEdge(dut.clk_i)
        await driver.initialize(bank_base)
        
        NUM_CYCLES = 1000
        for j in range(NUM_CYCLES): 
            await RisingEdge(dut.clk_i)
            dut.job_valid_i.value = 0 
            dut.worker_done_i.value = 0
            
            if rnd.random() < 0.5:     
                window_size = rnd.randint(1, 1024)
                await driver.set_job(window_size)
                
            if rnd.random() < 0.1:
                await driver.set_done_vector(golden_model.state['busy_workers'])

        score_board_task.kill()
        golden_model_task.kill()
        output_monitor_task.kill()
                