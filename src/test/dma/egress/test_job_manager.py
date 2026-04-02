import cocotb
import random as rnd
import math

from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotb.clock import Clock

class JobManagerDriver:
    def __init__(self, dut, n_streams):
        self.dut = dut
        self.n_streams = n_streams
        
        for s in range(self.n_streams):      
            self.dut.notif_valid_i[s].value = 0
            self.dut.notif_start_macro_i[s].value = 0
            self.dut.cfg_push_i[s].value = 0
            self.dut.cfg_wdata_i[s].value = 0
            self.dut.window_size_i[s].value = 0
        
        self.dut.job_ready_i.value = 0
            
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
        
    async def send_notification(self, stream_id, start_macro):
        self.dut.notif_valid_i[stream_id].value = 1
        self.dut.notif_start_macro_i[stream_id].value = start_macro
        
    async def send_configuration(self, stream_id, payload, apply_count, window_id):
        self.dut.cfg_push_i[stream_id].value = 1
        cfg = (payload << 32) | (apply_count << 16) | window_id
        self.dut.cfg_wdata_i[stream_id].value = cfg 
        
        
class GoldenModel:
    def __init__(self, n_streams, arbiter):
        self.n_streams = n_streams
        self.arbiter = arbiter  
        
    
        
        

class InputMonitor:
    def __init__(self, dut, golden_model, scoreboard):
        self.dut = dut
        self.golden_model = golden_model
        self.scoreboard = scoreboard


class OutputMonitor:
    def __init__(self, dut):
        self.dut = dut
        
        
class Scoreboard:
    pass


@cocotb.test()
async def test_job_manager_simple(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(dut.N_STREAMS.value)
    macro_ptr_width = math.log2(dut.M_MACROS.value)
    
    #arbiter = RRGoldenModel(n_streams)
    driver = JobManagerDriver(dut, n_streams)
    
    
    NUM_CYCLES = 100
    for _ in range(NUM_CYCLES):
        for stream_id in range(n_streams):
            window_size = rnd.getrandbits(32)
            dut.window_size_i[stream_id].value = window_size

        await driver.reset()
        
        await driver.send_notification(0, 7)
        cfg_payload = rnd.getrandbits(96)
        cfg_apply_count = rnd.randint(1, 16)
        cfg_window_id = 0
  
        await driver.send_configuration(0, cfg_payload, cfg_apply_count, cfg_window_id)
        await RisingEdge(dut.clk_i)
        dut.notif_valid_i[0].value = 0
        dut.cfg_push_i[0].value = 0
        
        await ClockCycles(dut.clk_i, 2)
        dut.job_ready_i.value = 1
        
        await ClockCycles(dut.clk_i, 10)
        