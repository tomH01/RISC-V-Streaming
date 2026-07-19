from enum import Enum

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

class BankState(Enum):
    FREE = 0
    OPEN = 1
    BUSY = 2
    CLOSING = 3
    FULL = 4

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
        self.dut.window_id_i.value = 0
        self.dut.payload_i.value = 0
        self.dut.job_valid_i.value = 0        

        for b in range(self.b_banks):
            self.dut.l2_bank_base_i[b].value = 0
        self.dut.bank_limit_b_i.value = 0
        self.dut.bank_header_size_b_i.value = 0
        self.dut.bank_owner_i.value = 0
        self.dut.bank_full_o.value = 0
        
        self.dut.worker_done_i.value = 0
        
        self.dut.meta_done_i.value = 0
        self.dut.meta_done_idx_i.value = 0
        self.dut.meta_ready_i.value = 0

    async def reset(self):
        self.dut.job_valid_i.value = 0
        self.dut.worker_done_i.value = 0
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)   
        
    async def initialize(self, bank_bases, bank_limit, bank_header_size):
        for b in range(self.b_banks):
            self.dut.l2_bank_base_i[b].value = bank_bases[b]
        self.dut.bank_limit_b_i.value = bank_limit
        self.dut.bank_header_size_b_i.value = bank_header_size 
        
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
        
    def start_mocks(self):
        mock_meta_task = cocotb.start_soon(self._mock_meta_writer())
        mock_cpu_task = cocotb.start_soon(self._mock_cpu())
        return mock_meta_task, mock_cpu_task

    async def _mock_meta_writer(self):
        close_q = []
        
        while True:
            await RisingEdge(self.dut.clk_i)
            
            self.dut.meta_done_i.value = 0
            self.dut.meta_done_idx_i.value = 0
            
            for i in range(len(close_q)):
                if close_q[i]["timer"] <= 0:
                    self.dut.meta_done_i.value = 1
                    self.dut.meta_done_idx_i.value = close_q[i]["idx"]
                    close_q.pop(i)
                    break
                else:
                    close_q[i]["timer"] -= 1
            
            self.dut.meta_ready_i.value = int(rnd.random() < 0.8)
            
            await ReadOnly()
            if self.dut.meta_close_bank_o.value == 1 and self.dut.meta_valid_o.value == 1 and self.dut.meta_ready_i.value == 1:
                close_q.append({
                    "idx": int(self.dut.meta_close_idx_o.value),
                    "timer": rnd.randint(5, 40)
                })
    
    async def _mock_cpu(self):
        owned_banks = set()
        
        while True:
            await RisingEdge(self.dut.clk_i)
            for b in list(owned_banks):
                if rnd.random() < 0.05:
                    owned_banks.remove(b)
            
            for b in range(self.b_banks):
                self.dut.bank_owner_i[b].value = int(b in owned_banks)
                
            await ReadOnly()
            for b in range(self.b_banks):
                if self.dut.bank_full_o[b].value == 1:
                    owned_banks.add(b)

    def _get_job_length(self):
        stream_id_len = len(self.dut.stream_id_i)
        start_macro_len = len(self.dut.start_macro_i)
        window_size_len = len(self.dut.window_size_i)
        mode_len = len(self.dut.mode_i)
        window_id_len = len(self.dut.window_id_i)
        payload_len = len(self.dut.payload_i)
        return stream_id_len + start_macro_len + window_size_len + mode_len + window_id_len + payload_len
        
    def _create_rnd_job(self, offset, window_size, window_size_len):
        clean_mask = ~(((1 << window_size_len) - 1) << offset)
        packed_job = int(rnd.getrandbits(self._get_job_length()))
        packed_job &= clean_mask
        packed_job |= (window_size << offset)
        return packed_job
        

class BankModel:
    def __init__(self):
        self.offset = 0
        self.stream_id = 0
        self.state = BankState.FREE
        self.active_worker = None
    
    def reset(self):
        self.offset = 0
        self.stream_id = 0
        self.state = BankState.FREE
        self.active_worker = None
        
    def is_available(self, is_cpu_owned):
        return not is_cpu_owned and (self.state == BankState.FREE or self.state == BankState.OPEN)
    
    
class GoldenModel:
    def __init__(self, dut, score_board, b_banks, w_workers):
        self.dut = dut
        self.scoreboard = score_board
        
        self.n_streams = int(params["N_STREAMS"])
        self.data_width = int(params["DATA_WIDTH"])
        self.b_banks = b_banks
        self.w_workers = w_workers
        self.bank_header_size = 0
        self.bank_limit = 0
        self.bank_bases = []
        
        self.banks = [BankModel() for _ in range(b_banks)]
        
    def reset(self):
        for bank in self.banks:
            bank.reset()
        
    async def initialize(self):
        await RisingEdge(self.dut.clk_i)
        await ReadOnly()
        
        self.bank_header_size = int(self.dut.bank_header_size_b_i.value)
        self.bank_limit = int(self.dut.bank_limit_b_i.value)
        self.bank_bases = [int(self.dut.l2_bank_base_i[b].value) for b in range(self.b_banks)]
        self.reset()

    def _allocate(self, stream_id, window_size_b):
        available_banks = [b for b in range(self.b_banks) if self.banks[b].is_available(int(self.dut.bank_owner_i[b].value))]

        def fits(b):
            return (self.banks[b].offset + self.bank_header_size + window_size_b) <= self.bank_limit
        
        match_fit = next((b for b in available_banks if fits(b) and stream_id == self.banks[b].stream_id and self.banks[b].state == BankState.OPEN), None)
        match_fail = next((b for b in available_banks if not fits(b) and stream_id == self.banks[b].stream_id and self.banks[b].state == BankState.OPEN), None)
        empty = next((b for b in available_banks if self.banks[b].state == BankState.FREE), None)
        any_fit = next((b for b in available_banks if fits(b)), None)
        
        target = None
        close_idx = None
        do_close = False
        
        if match_fail is not None:
            do_close = True
            close_idx = match_fail

        if match_fit is not None:
            target = match_fit
        elif empty is not None:
            target = empty
        elif any_fit is not None:
            target = any_fit
        else:
            all_banks_open = all(self.banks[b].state == BankState.OPEN for b in range(self.b_banks))
            if all_banks_open:
                do_close = True
                close_idx = 0            
                
        return target, do_close, close_idx

    def _get_idle_worker(self):
        busy_workers = {bank.active_worker for bank in self.banks if bank.active_worker is not None}
        for i in range(self.w_workers):
            if i not in busy_workers:
                return i
        return None

    async def run(self):        
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.rst_ni.value == 0:
                self.reset()
                continue

            job_valid = int(self.dut.job_valid_i.value) == 1
            meta_ready = int(self.dut.meta_ready_i.value) == 1
            window_size = int(self.dut.window_size_i.value)
            window_size_b = window_size * self.data_width // 8
            stream_id = int(self.dut.stream_id_i.value)
            
            idle_worker = self._get_idle_worker()
            target_bank, do_close, close_idx = self._allocate(stream_id, window_size_b)
            
            all_banks_open = all(self.banks[b].state == BankState.OPEN for b in range(self.b_banks))
            
            rtl_ready = int(self.dut.job_ready_o.value) == 1
            do_dispatch = job_valid and meta_ready and (idle_worker is not None) and (target_bank is not None) and (window_size > 0) and rtl_ready
            
            rtl_meta_ready = int(self.dut.meta_ready_i.value) == 1
            do_evict = job_valid and meta_ready and (target_bank is None) and do_close and all_banks_open and rtl_meta_ready
            
            if do_dispatch:
                addr_out = self.bank_bases[target_bank] + self.bank_header_size + self.banks[target_bank].offset
                
                self.scoreboard.add_expected_job({
                    'job_wid': idle_worker,
                    'job_addr': addr_out,
                    'job_bank': target_bank,
                    'stream_id': stream_id,
                    'start_macro': int(self.dut.start_macro_i.value),
                    'window_size': window_size,
                    'mode': int(self.dut.mode_i.value),
                    'window_id': int(self.dut.window_id_i.value),
                    'payload': int(self.dut.payload_i.value)
                })
                
            if do_dispatch or do_evict:
                self.scoreboard.add_expected_meta({
                    'close_bank': 1 if do_close else 0,
                    'dispatch_idx': target_bank if target_bank is not None else 0,
                    'close_idx': close_idx if close_idx is not None else 0,
                    'window_id': int(self.dut.window_id_i.value),
                    'window_size': window_size_b
                })

            next_states = [bank.state for bank in self.banks]
            next_offsets = [bank.offset for bank in self.banks]
            next_stream_ids = [bank.stream_id for bank in self.banks]
            next_workers = [bank.active_worker for bank in self.banks]
            
            for w in range(self.w_workers):
                if self.dut.worker_done_i[w].value == 1:
                    for b in range(self.b_banks):
                        if next_workers[b] == w:
                            next_workers[b] = None
                            if next_states[b] == BankState.BUSY:
                                next_states[b] = BankState.OPEN
                                
            if do_dispatch:
                next_states[target_bank] = BankState.BUSY
                next_workers[target_bank] = idle_worker
                next_offsets[target_bank] += window_size_b
                next_stream_ids[target_bank] = stream_id
                
            if (do_dispatch or do_evict) and do_close and close_idx is not None:
                next_states[close_idx] = BankState.CLOSING
            
            if int(self.dut.meta_done_i.value) == 1:
                done_idx = int(self.dut.meta_done_idx_i.value)
                next_states[done_idx] = BankState.FULL
                
            for b in range(self.b_banks):
                if int(self.dut.bank_owner_i[b].value) == 1:
                    next_states[b] = BankState.FREE
                    next_offsets[b] = 0
                    next_stream_ids[b] = 0
                    next_workers[b] = None
                 
            for b in range(self.b_banks):
                self.banks[b].state = next_states[b]
                self.banks[b].offset = next_offsets[b]
                self.banks[b].stream_id = next_stream_ids[b]
                self.banks[b].active_worker = next_workers[b]
                
    def get_busy_workers(self):
        return {bank.active_worker for bank in self.banks if bank.active_worker is not None}

        
class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.job_valid_o.value:
                self.scoreboard.add_actual_job({
                    'job_wid': int(self.dut.job_wid_o.value),
                    'job_addr': int(self.dut.job_addr_o.value),
                    'job_bank': int(self.dut.job_bank_o.value),
                    'stream_id': int(self.dut.stream_id_o.value),
                    'start_macro': int(self.dut.start_macro_o.value),
                    'window_size': int(self.dut.window_size_o.value),
                    'mode': int(self.dut.mode_o.value),
                    'window_id': int(self.dut.window_id_o.value),
                    'payload': int(self.dut.payload_o.value)
                })   
                
            if self.dut.meta_valid_o.value:
                self.scoreboard.add_actual_meta({
                    'close_bank': int(self.dut.meta_close_bank_o.value),
                    'dispatch_idx': int(self.dut.meta_dispatch_idx_o.value),
                    'close_idx': int(self.dut.meta_close_idx_o.value),
                    'window_id': int(self.dut.meta_window_id_o.value),
                    'window_size': int(self.dut.meta_window_size_o.value)
                })      
            
            
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
                await ClockCycles(self.dut.clk_i, 2)
                        
            assert exp['job_wid'] == act['job_wid'], f"Expected worker ID {exp['job_wid']}, got {act['job_wid']}"
            assert exp['job_addr'] == act['job_addr'], f"Expected job address {exp['job_addr']}, got {act['job_addr']}"
            assert exp['job_bank'] == act['job_bank'], f"Expected job bank {exp['job_bank']}, got {act['job_bank']}"
            assert exp['stream_id'] == act['stream_id'], f"Expected stream ID {exp['stream_id']}, got {act['stream_id']}"
            assert exp['start_macro'] == act['start_macro'], f"Expected start macro {exp['start_macro']}, got {act['start_macro']}"
            assert exp['window_size'] == act['window_size'], f"Expected window size {exp['window_size']}, got {act['window_size']}"
            assert exp['mode'] == act['mode'], f"Expected mode {exp['mode']}, got {act['mode']}"
            assert exp['window_id'] == act['window_id'], f"Expected window ID {exp['window_id']}, got {act['window_id']}"
            assert exp['payload'] == act['payload'], f"Expected payload {exp['payload']}, got {act['payload']}"

    async def compare_meta(self):
        while True:
            exp = await self.expected_meta_q.get()
            act = await self.actual_meta_q.get()
            
            if exp != act:
                await ClockCycles(self.dut.clk_i, 2)
            
            assert exp['close_bank'] == act['close_bank'], f"Expected close bank {exp['close_bank']}, got {act['close_bank']}"
            assert exp['dispatch_idx'] == act['dispatch_idx'], f"Expected dispatch index {exp['dispatch_idx']}, got {act['dispatch_idx']}"
            assert exp['close_idx'] == act['close_idx'], f"Expected close index {exp['close_idx']}, got {act['close_idx']}"
            assert exp['window_id'] == act['window_id'], f"Expected window ID {exp['window_id']}, got {act['window_id']}"
            assert exp['window_size'] == act['window_size'], f"Expected window size {exp['window_size']}, got {act['window_size']}"
            
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
    
    driver = L2AllocatorDriver(dut)
    
    for i in range(100):
        print(i)
        bank_bases = [rnd.randint(0, 1024) for _ in range(b_banks)]
        bank_limit = 32768
        bank_header_size = 1024
        await driver.initialize(bank_bases, bank_limit, bank_header_size)
        await driver.reset()
        
        score_board = Scoreboard(dut)
        golden_model = GoldenModel(dut, score_board, b_banks, w_workers)
        output_monitor = OutputMonitor(dut, score_board)
        
        await golden_model.initialize()   
        
        mock_meta_task, mock_cpu_taks =  driver.start_mocks()
        score_board_task = cocotb.start_soon(score_board.run())
        golden_model_task = cocotb.start_soon(golden_model.run())   
        output_monitor_task = cocotb.start_soon(output_monitor.monitor()) 
        
        NUM_CYCLES = 1000
        for j in range(NUM_CYCLES): 
            await RisingEdge(dut.clk_i)
            dut.job_valid_i.value = 0 
            dut.worker_done_i.value = 0
            
            if rnd.random() < 0.5:     
                window_size = rnd.randint(1, 4096)
                await driver.set_job(window_size)
                
            if rnd.random() < 0.1:
                await driver.set_done_vector(golden_model.get_busy_workers())

        mock_meta_task.kill()
        mock_cpu_taks.kill()
        score_board_task.kill()
        golden_model_task.kill()
        output_monitor_task.kill()
                