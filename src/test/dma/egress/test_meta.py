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


class MetaDriver:
    def __init__(self, dut):    
        self.dut = dut
        
        self.b_banks = int(params["B_BANKS"])
        self.w_workers = int(params["W_WORKERS"])
        
        self._init_signals()
        
    def _init_signals(self):
        self.dut.meta_req_i.value = 0
        self.dut.meta_addr_i.value = 0
        self.dut.meta_wen_i.value = 1
        self.dut.meta_wdata_i.value = 0
        self.dut.meta_be_i.value = 0
        
        self.dut.dispatch_valid_i.value = 0
        self.dut.dispatch_data_i.value = 0
        self.dut.dispatch_worker_id_i.value = 0
        
        self.dut.ptr_valid_i.value = 0
        self.dut.ptr_done_i.value = 0
        for w in range(self.w_workers):
            self.dut.ptr_stream_id_i[w].value = 0
            self.dut.ptr_i[w].value = 0
        
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)  
        
    async def send_dispatch_data(self, stream_id, size, base_addr, worker_id):
        data = ((stream_id & 0x1F) << 27) | ((size & 0x3FF) << 17) | (0x1FFFF & base_addr)
        self.dut.dispatch_valid_i.value = 1
        self.dut.dispatch_data_i.value = data
        self.dut.dispatch_worker_id_i.value = worker_id

    async def send_ptr_data(self, worker_id, stream_id, ptr, done):
        self.dut.ptr_valid_i[worker_id].value = 1
        self.dut.ptr_done_i[worker_id].value = done
        self.dut.ptr_stream_id_i[worker_id].value = stream_id
        self.dut.ptr_i[worker_id].value = ptr        
        
    async def invalidate_ptr(self, worker_id):
        self.dut.ptr_valid_i[worker_id].value = 0
        self.dut.ptr_stream_id_i[worker_id].value = 0
        self.dut.ptr_i[worker_id].value = 0
        
    async def req_stream_ptr(self, stream_id):
        addr = stream_id << 2
        
        self.dut.meta_req_i.value = 1
        self.dut.meta_addr_i.value = addr
        self.dut.meta_wen_i.value = 1
    
    async def req_dispatch_data(self):
        addr = 0x84
        
        self.dut.meta_req_i.value = 1
        self.dut.meta_addr_i.value = addr
        self.dut.meta_wen_i.value = 1
        
    async def send_cpu_done_ptr(self, ptr):
        addr = 0x80
        
        self.dut.meta_req_i.value = 1
        self.dut.meta_addr_i.value = addr
        self.dut.meta_wen_i.value = 0
        self.dut.meta_wdata_i.value = ptr
        
    @staticmethod
    def decode_dispatch_data(data):
        stream_id = (data >> 27) & 0x1F
        size = (data >> 17) & 0x3FF
        base_addr = data & 0x1FFFF
        return stream_id, size, base_addr


class DMAMock:
    def __init__(self, dut, driver):    
        self.dut = dut
        self.driver = driver
        
        self.n_streams = int(params["N_STREAMS"])
        self.data_width = int(params["DATA_WIDTH"])
        self.data_width_b= self.data_width // 8
        self.w_workers = int(params["W_WORKERS"])
        self.b_banks = int(params["B_BANKS"])
        self.bank_depth = int(params["BANK_DEPTH"])
        self.sram_size_b = self.bank_depth * self.b_banks * self.data_width_b
        self.ptr_width = math.log2(self.sram_size_b)
        
        self.dispatch_ptr = 0
        self.jobs = [None] * self.w_workers
        
    async def run(self):
        while True:
            await ReadOnly()
            cpu_done_ptr = int(self.dut.cpu_done_ptr_o.value)            
            
            await RisingEdge(self.dut.clk_i)
            self.dut.dispatch_valid_i.value = 0            
            
            dispatched_worker = -1
            if rnd.random() < 0.5:
                dispatched_worker = await self.dispatch_rnd_job(cpu_done_ptr)
                
                
            for w, job in enumerate(self.jobs):
                if job is not None and dispatched_worker != w:
                    is_last_word = (job["ptr"] == (job["base_addr"] + job["size"] - self.data_width_b) % self.sram_size_b)
                    
                    if is_last_word:
                        self.jobs[w] = None
                        await self.driver.send_ptr_data(w, job["stream_id"], job["ptr"], done=1)
                    else: 
                        if rnd.random() < 0.8:
                            job["ptr"] = (job["ptr"] + self.data_width_b) % self.sram_size_b
                            await self.driver.send_ptr_data(w, job["stream_id"], job["ptr"], done=0)
                            
                elif job is None and dispatched_worker != w:
                    await self.driver.invalidate_ptr(w)
            
    async def dispatch_rnd_job(self, cpu_done_ptr):
        new_job = self._get_rnd_job()        
        
        occupied_bytes = (self.dispatch_ptr - cpu_done_ptr) % self.sram_size_b
        is_space_available = (occupied_bytes + new_job["size"]) < self.sram_size_b
        
        if is_space_available:
            for w, _ in enumerate(self.jobs):
                if self.jobs[w] is None:
                    self.jobs[w] = {
                        "stream_id": new_job["stream_id"], 
                        "size": new_job["size"], 
                        "base_addr": self.dispatch_ptr, 
                        "ptr": self.dispatch_ptr
                    }
                    await self.driver.send_dispatch_data(new_job["stream_id"], new_job["size"], self.dispatch_ptr, w)
                    self.dispatch_ptr = (self.dispatch_ptr + new_job["size"]) % self.sram_size_b
                    return w
                
    def _get_rnd_job(self):
        return {
            "stream_id": rnd.randrange(self.n_streams),
            "size": rnd.randint(1, 1024) * self.data_width_b, 
        } 
        

class GoldenModel:
    def __init__(self, dut, driver, scoreboard):
        self.dut = dut
        self.driver = driver
        self.scoreboard = scoreboard
        
        self.n_streams = int(params["N_STREAMS"])
        self.w_workers = int(params["W_WORKERS"])
        self.bank_depth = int(params["BANK_DEPTH"])
        self.b_banks = int(params["B_BANKS"])
        self.data_width = int(params["DATA_WIDTH"])
        self.data_width_b = int(params["DATA_WIDTH"]) // 8
        self.sram_size_b = self.bank_depth * self.b_banks * self.data_width_b
        
        self.stream_ptrs = [0] * int(params["N_STREAMS"])
        self.cpu_done_ptr = 0
        self.fifo = deque()
        self.order_fifos = [deque() for _ in range(self.n_streams)]
        self.retired_workers = [set() for _ in range(self.n_streams)]
        
        
    async def run(self):
        cpu_done_ptr_write = False
        cpu_done_ptr_temp = 0
        
        await ReadOnly()
        while True:    
            req = int(self.dut.meta_req_i.value)
            gnt = int(self.dut.meta_gnt_o.value)
            addr = int(self.dut.meta_addr_i.value)
            wen = int(self.dut.meta_wen_i.value)
            wdata = int(self.dut.meta_wdata_i.value)
            
            current_fifo_r_req = (req == 1 and gnt == 1 and addr == 0x84 and wen == 1)
            
            if req == 1 and gnt == 1 and addr == 0x80 and wen == 0:
                cpu_done_ptr_write = True
                cpu_done_ptr_temp = wdata
                
            await RisingEdge(self.dut.clk_i)
            self.dut.meta_req_i.value = 0
            
            distances = [(ptr - self.cpu_done_ptr) % self.sram_size_b for ptr in self.stream_ptrs]
            max_advance_b = min(distances)
            increment = rnd.randint(0, max_advance_b // self.data_width_b) * self.data_width_b
            
            if max_advance_b > 0:
                cpu_done_ptr = (self.cpu_done_ptr + increment) % self.sram_size_b
                await self.driver.send_cpu_done_ptr(cpu_done_ptr)
                
            await ReadOnly()
            
            actual = {}
            
            for s in range(self.n_streams):
                actual[f"stream_ptr_{s}"] = self.stream_ptrs[s]
                
            actual["cpu_done_ptr"] = self.cpu_done_ptr
                
                
            if current_fifo_r_req:
                if len(self.fifo) > 0:
                    actual["dispatch_data"] = self.fifo.popleft()
                else:
                    raise Exception("FIFO read pending but no data available.")
                
            self.scoreboard.add_expected(actual)
            
            # fifo
            if int(self.dut.dispatch_valid_i.value) == 1 and int(self.dut.dispatch_ready_o.value) == 1:
                data = int(self.dut.dispatch_data_i.value)
                self.fifo.append(data)
                
            # stream ptrs    
            for w in range(self.w_workers):
                if (self.dut.ptr_done_i[w].value) == 1 and (self.dut.ptr_valid_i[w].value) == 1:
                    stream_id = int(self.dut.ptr_stream_id_i[w].value)
                    self.retired_workers[stream_id].add(w)
                    
            if int(self.dut.dispatch_valid_i.value) == 1 and int(self.dut.dispatch_ready_o.value) == 1:
                data = int(self.dut.dispatch_data_i.value)
                stream_id, _, _ = self.driver.decode_dispatch_data(data)
                worker_id = int(self.dut.dispatch_worker_id_i.value)
                self.order_fifos[stream_id].append(worker_id)
                
            for i in range(self.n_streams):
                if len(self.order_fifos[i]) > 0:
                    top_w = self.order_fifos[i][0]

                    if int(self.dut.ptr_valid_i[top_w].value) == 1:
                        self.stream_ptrs[i] = int(self.dut.ptr_i[top_w].value)
                        
                    top_is_retired = top_w in self.retired_workers[i]
                    top_has_done = int(self.dut.ptr_done_i[top_w].value) == 1 and \
                                   int(self.dut.ptr_stream_id_i[top_w].value) == i and \
                                   int(self.dut.ptr_valid_i[top_w].value) == 1
                                   
                    if top_is_retired or top_has_done:
                        self.order_fifos[i].popleft()
                        if top_w in self.retired_workers[i]:
                            self.retired_workers[i].remove(top_w)

            # cpu done ptr
            if cpu_done_ptr_write:
                self.cpu_done_ptr = cpu_done_ptr_temp
                cpu_done_ptr_write = False
        
class OutputMonitor:
    def __init__(self, dut, scoreboard, driver, mode):
        self.dut = dut
        self.scoreboard = scoreboard
        self.driver = driver
        self.mode = mode
        
        self.n_streams = int(params["N_STREAMS"])
        
    async def monitor(self):
        pipeline = []
        
        while True:
            await ReadOnly()
            
            finished_read = None
            for i, read in enumerate(pipeline):
                if read[0] == 0:
                    finished_read = read
                    pipeline.pop(i)
                    break
            
            if finished_read is not None:
                _, rtype, stream_id = finished_read
                
                valid = int(self.dut.meta_r_valid_o.value)
                rdata = int(self.dut.meta_r_rdata_o.value)
                
                if valid == 1:
                    if rtype == "stream_ptrs":
                        actual = {
                            f"stream_ptr_{stream_id}": rdata
                        }
                        self.scoreboard.add_actual(actual)
                    elif rtype == "dispatch":
                        actual = {
                            "dispatch_data": rdata
                        }
                        self.scoreboard.add_actual(actual)
                    
            if self.mode == "cpu_done_ptr":
                actual = {
                    "cpu_done_ptr": int(self.dut.cpu_done_ptr_o.value)
                }
                self.scoreboard.add_actual(actual)
                
            for read in pipeline:
                read[0] -= 1
                
            await RisingEdge(self.dut.clk_i)
            self.dut.meta_req_i.value = 0
            
            if self.mode == "stream_ptrs":
                req_stream_id = rnd.randrange(self.n_streams)
                await self.driver.req_stream_ptr(req_stream_id)
                pipeline.append([1, "stream_ptrs", req_stream_id])
                    
            elif self.mode == "dispatch":
                await self.driver.req_dispatch_data()
                pipeline.append([1, "dispatch", None])
        

class Scoreboard:
    def __init__(self, dut, mode):
        self.dut = dut
        self.mode = mode
        
        self.expected_q = Queue()
        self.actual_q = Queue()
        
    def add_expected(self, value):
        self.expected_q.put_nowait(value)
        
    def add_actual(self, value):        
        self.actual_q.put_nowait(value)
        
    async def compare(self):
        while True:
            actual = await self.actual_q.get()
            while True:
                expected = await self.expected_q.get()
                if "dispatch_data" in actual and "dispatch_data" not in expected:
                    continue
                break
            
            for key, value in actual.items():
                if expected[key] != value:
                    await ClockCycles(self.dut.clk_i, 2)
                assert expected[key] == value, f"{key}: Expected: {expected[key]}, Actual: {actual[key]}"
            
    async def run(self):
        cocotb.start_soon(self.compare())
        
async def test_meta(dut, mode):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    scoreboard = Scoreboard(dut, mode)
    cocotb.start_soon(scoreboard.run())
    
    driver = MetaDriver(dut)
    await driver.reset()
    
    output_monitor = OutputMonitor(dut, scoreboard, driver, mode=mode)
    cocotb.start_soon(output_monitor.monitor())
    
    golden_model = GoldenModel(dut, driver, scoreboard)
    cocotb.start_soon(golden_model.run())
    
    dma_mock = DMAMock(dut, driver)
    cocotb.start_soon(dma_mock.run())
    
    NUM_CYCLES = 100000
    for _ in range(NUM_CYCLES):
        await RisingEdge(dut.clk_i)
        
@cocotb.test()
async def test_meta_cpu_ptr(dut):
    await test_meta(dut, mode="cpu_done_ptr")
    
@cocotb.test()
async def test_meta_stream_ptrs(dut):
    await test_meta(dut, mode="stream_ptrs")

@cocotb.test()
async def test_meta_dispatch(dut):
    await test_meta(dut, mode="dispatch")
