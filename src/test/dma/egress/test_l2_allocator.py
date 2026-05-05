import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotb.clock import Clock


class L2AllocatorDriver:
    def __init__(self, dut, b_banks, w_workers):   
        self.dut = dut
        self.b_banks = b_banks
        self.w_workers = w_workers
        
        self.job_length = self.get_job_length()
        
        self.dut.stream_id_i.value = 0
        self.dut.start_macro_i.value = 0
        self.dut.window_size_i.value = 0
        self.dut.mode_i.value = 0
        self.dut.window_id_i.value = 0
        self.dut.payload_i.value = 0
        self.dut.job_valid_i.value = 0        

        self.dut.start_bank_idx_i.value = 0
        for b in range(self.b_banks):
            self.dut.l2_bank_base_i[b].value = 0
        self.dut.bank_limit_b_i.value = 0
        self.dut.bank_header_size_b_i.value = 0
        
        self.dut.worker_done_i.value = 0

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)   
        
    async def initialize(self, start_bank_idx, bank_bases, bank_limit, bank_header_size):
        self.dut.start_bank_idx_i.value = start_bank_idx
        for b in range(self.b_banks):
            self.dut.l2_bank_base_i[b].value = bank_bases[b]
        self.dut.bank_limit_b_i.value = bank_limit
        self.dut.bank_header_size_b_i.value = bank_header_size 
        await RisingEdge(self.dut.clk_i)
        
    async def set_job(self, window_size):        
        payload_len = len(self.dut.payload_i)
        window_id_len = len(self.dut.window_id_i)
        mode_len = len(self.dut.mode_i)
        window_size_len = len(self.dut.window_size_i)
        start_macro_len = len(self.dut.start_macro_i)
        stream_id_len = len(self.dut.stream_id_i)
        theo_len = payload_len + window_id_len + mode_len + window_size_len + start_macro_len + stream_id_len
        
        offset = payload_len + window_id_len + mode_len
        packed_job = self._create_rnd_job(offset, window_size, window_size_len)
        low_bit = 0
        
        self.dut.job_valid_i.value = 1
        
        self.dut.payload_i.value = (packed_job >> low_bit) & ((1 << payload_len) - 1)
        low_bit += payload_len
        
        self.dut.window_id_i.value = (packed_job >> low_bit) & ((1 << window_id_len) - 1)
        low_bit += window_id_len
        
        self.dut.mode_i.value = (packed_job >> low_bit) & ((1 << mode_len) - 1)
        low_bit += mode_len
        
        self.dut.window_size_i.value = int((packed_job >> low_bit) & ((1 << window_size_len) - 1))
        low_bit += window_size_len
        
        self.dut.start_macro_i.value = int((packed_job >> low_bit) & ((1 << start_macro_len) - 1))
        low_bit += start_macro_len
        
        self.dut.stream_id_i.value = int((packed_job >> low_bit) & ((1 << stream_id_len) - 1))
        return packed_job
    
    async def set_done_vector(self, busy_indices):
        if not busy_indices:
            self.dut.worker_done_i.value = 0
            return
        
        busy_indices = list(busy_indices)
        n_busy = len(busy_indices)
        
        k_options = list(range(1, n_busy + 1))
        weights = [1.0 / (2**k) for k in k_options]
        
        num_dones = rnd.choices(k_options, weights=weights, k=1)[0]
        
        ones_indices = rnd.sample(busy_indices, num_dones)
        self.dut.worker_done_i.value = sum(1 << i for i in ones_indices)

    def get_job_length(self):
        stream_id_len = len(self.dut.stream_id_i)
        start_macro_len = len(self.dut.start_macro_i)
        window_size_len = len(self.dut.window_size_i)
        mode_len = len(self.dut.mode_i)
        window_id_len = len(self.dut.window_id_i)
        payload_len = len(self.dut.payload_i)
        return stream_id_len + start_macro_len + window_size_len + mode_len + window_id_len + payload_len
        
    def _create_rnd_job(self, offset, window_size, window_size_len):
        clean_mask = ~(((1 << window_size_len) - 1) << offset)
        packed_job = int(rnd.getrandbits(self.job_length))
        packed_job &= clean_mask
        packed_job |= (window_size << offset)
        return packed_job
    
    
class GoldenModel:
    def __init__(self, dut, score_board):
        self.dut = dut
        self.scoreboard = score_board
        
        self.b_banks = int(self.dut.B_BANKS)
        self.w_workers = int(self.dut.W_WORKERS)
        self.bank_header_size = None
        self.bank_limit = None
        self.bank_bases = None
        
        self.state = {
            'current_bank': None,
            'current_addr': None,
            'bank_assignments': [set() for _ in range(self.b_banks)]
        }
        
    def reset(self):
        self.state['current_bank'] = None
        self.state['current_addr'] = None
        self.state['bank_assignments'] = [set() for _ in range(self.b_banks)]
        
    async def initialize(self):
        await RisingEdge(self.dut.clk_i)
        await ReadOnly()
        
        self.bank_header_size = int(self.dut.bank_header_size_b_i.value)
        self.bank_limit = int(self.dut.bank_limit_b_i.value)
        self.bank_bases = [int(self.dut.l2_bank_base_i[b].value) for b in range(self.b_banks)]

        self.state["current_bank"] = int(self.dut.start_bank_idx_i.value)
        self.state["current_addr"] = self.bank_bases[self.state["current_bank"]] + self.bank_header_size
        

    async def run(self):        
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.rst_ni.value == 0:
                self.reset()
                await ClockCycles(self.dut.clk_i, 2)
                continue
            
            
            window_size = int(self.dut.window_size_i.value)
            
            job_valid = int(self.dut.job_valid_i.value)
            next_bank_idx = self.get_bank_idx(window_size)
            worker_idx = self.get_idle_worker()
            
            # Dispatch
            if job_valid and next_bank_idx is not None and worker_idx is not None:
                if self.fits_in_current_bank(window_size):
                    addr_out = self.state["current_addr"]
                    self.state["current_addr"] += window_size
                else:
                    addr_out = self.bank_bases[next_bank_idx] + self.bank_header_size
                    self.state["current_bank"] = next_bank_idx
                    self.state["current_addr"] = addr_out + window_size
                
                self.state["bank_assignments"][next_bank_idx].add(worker_idx)
                
                result = {
                    'job_wid': worker_idx,
                    'job_addr': addr_out,
                    'job_bank': next_bank_idx,
                    'stream_id': int(self.dut.stream_id_i.value),
                    'start_macro': int(self.dut.start_macro_i.value),
                    'window_size': window_size,
                    'mode': int(self.dut.mode_i.value),
                    'window_id': int(self.dut.window_id_i.value),
                    'payload': int(self.dut.payload_i.value)
                }
                self.scoreboard.add_expected(result)         
                
            self.discard_assignments(self.dut.worker_done_i)
            
            
    def get_bank_idx(self, window_size):
        current_bank = self.state["current_bank"]
        
        if self.fits_in_current_bank(window_size):
            return current_bank
        
        next_bank = (current_bank + 1) % self.b_banks
        if not self.is_bank_busy(next_bank):
            return next_bank
        
        return None
    
    def is_bank_busy(self, bank_idx):
        is_active = (bank_idx == self.state["current_bank"])
        has_active_workers = len(self.state["bank_assignments"][bank_idx]) > 0
        return is_active or has_active_workers
    
    def get_idle_worker(self):
        for i in range(self.w_workers):
            if i not in self.get_busy_workers():
                return i
        return None
        
    def fits_in_current_bank(self, window_size):
        new_addr = self.state["current_addr"] + window_size
        return new_addr <= self.bank_bases[self.state["current_bank"]] + self.bank_limit
        
    def discard_assignments(self, done_vector):
        for i in range(self.w_workers):
            if done_vector[i].value == 1:
                for bank_set in self.state['bank_assignments']:
                    bank_set.discard(i)
                    
    def get_busy_workers(self):
        return set().union(*self.state["bank_assignments"])
        
            
class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.job_valid_o.value:
                result = {
                    'job_wid': int(self.dut.job_wid_o.value),
                    'job_addr': int(self.dut.job_addr_o.value),
                    'job_bank': int(self.dut.job_bank_o.value),
                    'stream_id': int(self.dut.stream_id_o.value),
                    'start_macro': int(self.dut.start_macro_o.value),
                    'window_size': int(self.dut.window_size_o.value),
                    'mode': int(self.dut.mode_o.value),
                    'window_id': int(self.dut.window_id_o.value),
                    'payload': int(self.dut.payload_o.value)
                }
                self.scoreboard.add_actual(result)         
            
            
class Scoreboard:
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
            exp = await self.expected_q.get()
            act = await self.actual_q.get()
            
            if exp != act:
                await ClockCycles(self.dut.clk_i, 5)
                        
            assert exp['job_wid'] == act['job_wid'], f"Expected worker ID {exp['job_wid']}, got {act['job_wid']}"
            assert exp['job_addr'] == act['job_addr'], f"Expected job address {exp['job_addr']}, got {act['job_addr']}"
            assert exp['job_bank'] == act['job_bank'], f"Expected job bank {exp['job_bank']}, got {act['job_bank']}"
            assert exp['stream_id'] == act['stream_id'], f"Expected stream ID {exp['stream_id']}, got {act['stream_id']}"
            assert exp['start_macro'] == act['start_macro'], f"Expected start macro {exp['start_macro']}, got {act['start_macro']}"
            assert exp['window_size'] == act['window_size'], f"Expected window size {exp['window_size']}, got {act['window_size']}"
            assert exp['mode'] == act['mode'], f"Expected mode {exp['mode']}, got {act['mode']}"
            assert exp['window_id'] == act['window_id'], f"Expected window ID {exp['window_id']}, got {act['window_id']}"
            assert exp['payload'] == act['payload'], f"Expected payload {exp['payload']}, got {act['payload']}"

    def clear(self):
        while not self.expected_q.empty():
            self.expected_q.get_nowait()
        while not self.actual_q.empty():
            self.actual_q.get_nowait()
            
    async def run(self):
        await self.compare() 
           

@cocotb.test()
async def test_l2_allocator_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    b_banks = int(dut.B_BANKS.value)
    w_workers = int(dut.W_WORKERS.value)
    
    driver = L2AllocatorDriver(dut, b_banks, w_workers)
    score_board = Scoreboard(dut)
    golden_model = GoldenModel(dut, score_board)
    output_monitor = OutputMonitor(dut, score_board)
    
    cocotb.start_soon(score_board.run())
    
    for _ in range(1):
        await driver.reset()
        
        start_bank_idx = rnd.randint(0, b_banks - 1)
        bank_bases = [rnd.randint(0, 1024) for _ in range(b_banks)]
        bank_limit = 32768
        bank_header_size = 1024
        await driver.initialize(start_bank_idx, bank_bases, bank_limit, bank_header_size)
        
        score_board.clear()
        
        golden_model.reset()
        await golden_model.initialize()   
        golden_model_task = cocotb.start_soon(golden_model.run())   
        output_monitor_task = cocotb.start_soon(output_monitor.monitor()) 
        
        NUM_CYCLES = 10000
        for j in range(NUM_CYCLES): 
            await RisingEdge(dut.clk_i)
            dut.job_valid_i.value = 0 
            dut.worker_done_i.value = 0
            
            if rnd.random() < 0.5:     
                window_size = rnd.randint(1, 4096)
                await driver.set_job(window_size)
                
            if rnd.random() < 0.1:
                await driver.set_done_vector(golden_model.get_busy_workers())

                
                
        golden_model_task.kill()
        output_monitor_task.kill()
                