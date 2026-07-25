import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from utils.python.cocotb import get_design_parameters

from apb_driver import APBDriver
params = get_design_parameters()


class PerformanceMonitorDriver:
    def __init__(self, dut):    
        self.dut = dut
        
        self.n_streams = int(params["N_STREAMS"])
        self.b_banks = int(params["B_BANKS"])
        self.w_workers = int(params["W_WORKERS"])
        
        self._init_signals()
        
        self.apb_driver = APBDriver(dut)
        
    def _init_signals(self):
        self.dut.dma_enable_i.value = 0
        
        self.dut.ingr_stm_in_valid_i.value = 0
        self.dut.ingr_stm_in_ready_i.value = 0
        
        self.dut.egr_job_req_valid_i.value = 0
        self.dut.egr_job_req_ready_i.value = 0
        self.dut.egr_meta_disp_valid_i.value = 0
        self.dut.egr_meta_disp_ready_i.value = 0
        self.dut.egr_wkr_bp_req_i.value = 0
        self.dut.egr_wkr_bp_gnt_i.value = 0
        self.dut.egr_wkr_bus_valid_i.value = 0
        self.dut.egr_wkr_bus_ready_i.value = 0
        
        self.dut.cpu_l2_valid_i.value = 0
        self.dut.cpu_l2_ready_i.value = 0
        self.dut.cpu_meta_req_i.value = 0
        self.dut.cpu_meta_gnt_i.value = 0
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    def drive_rnd_probes(self, dma_enabled=False):
        self.dut.dma_enable_i.value = int(dma_enabled)
        
        self.dut.ingr_stm_in_valid_i.value = int(rnd.getrandbits(self.n_streams))
        self.dut.ingr_stm_in_ready_i.value = int(rnd.getrandbits(self.n_streams))    
        
        self.dut.egr_job_req_valid_i.value  = rnd.randint(0, 1)
        self.dut.egr_job_req_ready_i.value = rnd.randint(0, 1)
        self.dut.egr_meta_disp_valid_i.value = rnd.randint(0, 1)
        self.dut.egr_meta_disp_ready_i.value = rnd.randint(0, 1)
        self.dut.egr_wkr_bp_req_i.value = int(rnd.getrandbits(self.w_workers))
        self.dut.egr_wkr_bp_gnt_i.value = int(rnd.getrandbits(self.w_workers))
        self.dut.egr_wkr_bus_valid_i.value = int(rnd.getrandbits(self.w_workers))
        self.dut.egr_wkr_bus_ready_i.value = int(rnd.getrandbits(self.w_workers))
        
        self.dut.cpu_l2_valid_i.value = rnd.randint(0, 1)
        self.dut.cpu_l2_ready_i.value = rnd.randint(0, 1)
        self.dut.cpu_meta_req_i.value = rnd.randint(0, 1)
        self.dut.cpu_meta_gnt_i.value = rnd.randint(0, 1)
    
    async def read_word_offset(self, word_offset):
        BASE_ADDR = 0x08004000
        
        addr = BASE_ADDR + word_offset * 4
        return await self.apb_driver.apb_read(addr)
        
        
        
class GoldenModel:
    def __init__(self, dut):
        self.dut = dut

        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
                
        self.dma_enabled = False
        
        self.counters = {}
        self.next_counters = {}
        
    def reset_counters(self):
        self.dma_enabled = False
        
        # Globals / Fixed
        self.counters = {
            0x000: 0, # setup_cnt
            0x001: 0, # run_cnt
            0x002: 0, # egr_job_req_hs
            0x003: 0, # egr_job_req_bp
            0x004: 0, # egr_meta_disp_hs
            0x005: 0, # egr_meta_disp_bp
            0x006: 0, # cpu_l2_hs
            0x007: 0, # cpu_l2_bp
            0x008: 0, # cpu_meta_hs
            0x009: 0  # cpu_meta_bp
        }
        
        # Streams (Start bei 0x040)
        for i in range(self.n_streams):
            self.counters[0x040 + 2 * i]     = 0 # HS
            self.counters[0x040 + 2 * i + 1] = 0 # BP

        # Workers (Start bei 0x080)
        for w in range(self.w_workers):
            self.counters[0x080 + 4 * w]     = 0 # BP HS
            self.counters[0x080 + 4 * w + 1] = 0 # BP BP
            self.counters[0x080 + 4 * w + 2] = 0 # BUS HS
            self.counters[0x080 + 4 * w + 3] = 0 # BUS BP
        
    async def run(self):
        while True:
            await ReadOnly()
            
            if int(self.dut.rst_ni.value) == 0:
                self.reset_counters()
                self.next_counters = self.counters.copy()
                await RisingEdge(self.dut.clk_i)
                continue
            
            dma_en = int(self.dut.dma_enable_i.value)
            
            self.next_counters = self.counters.copy()
            
            if not dma_en and not self.dma_enabled:
                self.next_counters[0x000] += 1
            elif dma_en:
                self.next_counters[0x001] += 1
                
                # In-Streams
                for s in range(self.n_streams):
                    stm_in_valid = int(self.dut.ingr_stm_in_valid_i[s].value)
                    stm_in_ready = int(self.dut.ingr_stm_in_ready_i[s].value)
                    
                    if stm_in_valid and stm_in_ready:
                        self.next_counters[0x040 + 2 * s] += 1
                    elif stm_in_valid and not stm_in_ready:
                        self.next_counters[0x040 + 2 * s + 1] += 1
                
                # Egress
                job_valid = int(self.dut.egr_job_req_valid_i.value)
                job_ready = int(self.dut.egr_job_req_ready_i.value) 
                
                if job_valid and job_ready:
                    self.next_counters[0x002] += 1
                elif job_valid and not job_ready:
                    self.next_counters[0x003] += 1
                    
                meta_valid = int(self.dut.egr_meta_disp_valid_i.value)
                meta_ready = int(self.dut.egr_meta_disp_ready_i.value)
                
                if meta_valid and meta_ready:
                    self.next_counters[0x004] += 1
                elif meta_valid and not meta_ready:
                    self.next_counters[0x005] += 1
                    
                # Workers
                for w in range(self.w_workers):
                    wkr_bp_req = int(self.dut.egr_wkr_bp_req_i[w].value)
                    wkr_bp_gnt = int(self.dut.egr_wkr_bp_gnt_i[w].value)
                    wkr_bus_valid = int(self.dut.egr_wkr_bus_valid_i[w].value)
                    wkr_bus_ready = int(self.dut.egr_wkr_bus_ready_i[w].value)
                    
                    if wkr_bp_req and wkr_bp_gnt:
                        self.next_counters[0x080 + 4 * w] += 1
                    elif wkr_bp_req and not wkr_bp_gnt:
                        self.next_counters[0x080 + 4 * w + 1] += 1
                        
                    if wkr_bus_valid and wkr_bus_ready:
                        self.next_counters[0x080 + 4 * w + 2] += 1
                    elif wkr_bus_valid and not wkr_bus_ready:
                        self.next_counters[0x080 + 4 * w + 3] += 1
                        
                # CPU
                cpu_l2_valid = int(self.dut.cpu_l2_valid_i.value)
                cpu_l2_ready = int(self.dut.cpu_l2_ready_i.value)
                
                if cpu_l2_valid and cpu_l2_ready:
                    self.next_counters[0x006] += 1
                elif cpu_l2_valid and not cpu_l2_ready:
                    self.next_counters[0x007] += 1
                    
                cpu_meta_req = int(self.dut.cpu_meta_req_i.value)
                cpu_meta_gnt = int(self.dut.cpu_meta_gnt_i.value)
                
                if cpu_meta_req and cpu_meta_gnt:
                    self.next_counters[0x008] += 1
                elif cpu_meta_req and not cpu_meta_gnt:
                    self.next_counters[0x009] += 1
            
            await RisingEdge(self.dut.clk_i)
            
            self.counters = self.next_counters.copy()
            if dma_en: 
                self.dma_enabled = True
                
    def get_expected(self, word_idx):
        return self.counters.get(word_idx, 0)
                        
        
class Scoreboard:
    def __init__(self, dut):
        self.dut = dut
        self.expected_q = Queue()
        self.actual_q = Queue()


    def add_expected(self, value):
        self.expected_q.put_nowait(value)

    def add_actual(self, value):
        self.actual_q.put_nowait(value)

    async def compare_jobs(self):
        while True:
            exp = await self.expected_q.get()
            act = await self.actual_q.get()
            
            assert exp == act, f"Scoreboard mismatch: expected {exp}, got {act}"
            print(f"Scoreboard match: expected {exp}, got {act}")
    async def run(self):
        cocotb.start_soon(self.compare_jobs())
        
        
@cocotb.test()
async def test_performance_monitor_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start()) 
    
    n_streams = int(params["N_STREAMS"])
    w_workers = int(params["W_WORKERS"])
    
    valid_word_offsets = list(range(0x000, 0x00A))
    for s in range(n_streams):
        valid_word_offsets.append(0x040 + 2 * s)
        valid_word_offsets.append(0x040 + 2 * s + 1)
    for w in range(w_workers):
        valid_word_offsets.append(0x080 + 4 * w)
        valid_word_offsets.append(0x080 + 4 * w + 1)
        valid_word_offsets.append(0x080 + 4 * w + 2)
        valid_word_offsets.append(0x080 + 4 * w + 3)
    
    driver = PerformanceMonitorDriver(dut)
    scoreboard = Scoreboard(dut)
    golden_model = GoldenModel(dut)
    
    cocotb.start_soon(golden_model.run())
    await driver.reset()
    
    cocotb.start_soon(scoreboard.run())
    
    SETUP_CYCLES = 50
    for _ in range(SETUP_CYCLES):
        driver.drive_rnd_probes(dma_enabled=False)
        await RisingEdge(dut.clk_i)
        
    driver.drive_rnd_probes(dma_enabled=True)
    await RisingEdge(dut.clk_i)
            
    setup_cnt_addr = 0x000
    exp_setup = golden_model.get_expected(setup_cnt_addr)
    actual_setup = await driver.read_word_offset(setup_cnt_addr)
    assert exp_setup == actual_setup, f"Setup counter mismatch: expected {exp_setup}, got {actual_setup}"
    
    NUM_CYCLES = 100000
    for i in range(NUM_CYCLES):
        dma_active = (i > 100 and (i % 100) < 10)
        driver.drive_rnd_probes(dma_enabled=dma_active)
        
        if (i % rnd.randint(2, 5)) == 0:
            target_word = rnd.choice(valid_word_offsets)
            
            
            actual_value = await driver.read_word_offset(target_word)
            scoreboard.add_actual(actual_value)
            
            exp_value = golden_model.get_expected(target_word)
            scoreboard.add_expected(exp_value)
        else: 
            await RisingEdge(dut.clk_i)
            
    await ClockCycles(dut.clk_i, 10)
            