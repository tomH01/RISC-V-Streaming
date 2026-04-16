import cocotb
import random as rnd
import numpy as np
import math

from collections import deque

from cocotb.queue import Queue
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
        
    async def send_configuration(self, stream_id, cfg_dict):
        
        self.dut.cfg_push_i[stream_id].value = 1
        
        cfg = int(cfg_dict["mode"] << 124) | int(cfg_dict["apply_count"] << 112) | int(cfg_dict["window_id"] << 96) | cfg_dict["payload"]
        self.dut.cfg_wdata_i[stream_id].value = cfg
    
    @staticmethod
    def get_rnd_window_id(current_window_id):
        int16_max = 2**16 - 1
        win_id = rnd.gauss(current_window_id, 3)
        return np.clip(int(win_id), 0, int16_max - current_window_id)
        
        
class GoldenModel:
    def __init__(self, dut, score_board, n_streams, fifo_depth):
        self.dut = dut
        self.scoreboard = score_board
        self.n_streams = n_streams
        self.fifo_depth = fifo_depth

        self.state = {s: {
            'notif_fifo': deque(maxlen=self.fifo_depth),
            'cfg_fifo': deque(maxlen=self.fifo_depth),
            'window_size': 0,
            'current_window_id': 0,
            'current_cfg': None,
            'apply_counter': 0,
        } for s in range(n_streams)
        }
        
    def reset(self):
        for s in range(self.n_streams):
            self.state[s]['notif_fifo'].clear()
            self.state[s]['cfg_fifo'].clear()
            self.state[s]['current_window_id'] = 0
            self.state[s]['current_cfg'] = None
            self.state[s]['apply_counter'] = 0
            
    async def run(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.rst_ni.value == 0:
                self.reset()
                continue
            
            for s in range(self.n_streams):
                st = self.state[s]
                
                st['window_size'] = int(self.dut.window_size_i[s].value)
                
                if st['cfg_fifo'] and st['cfg_fifo'][0]['window_id'] <= st['current_window_id']:
                    cfg = st['cfg_fifo'].popleft()
                    
                    if cfg['window_id'] == st['current_window_id']:
                        st['current_cfg'] = cfg
                        st['apply_counter'] = 0
            
            gnt_val = self.dut.dut.u_stream_arbiter.gnt_o.value.integer
            arb_valid = self.dut.dut.u_stream_arbiter.valid_o.value.integer
            us_ready = self.dut.dut.us_job_ready.value.integer
            
            if arb_valid and us_ready and gnt_val > 0:
                grant_id = int(math.log2(gnt_val))
                st = self.state[grant_id]
                
                if not st['notif_fifo']:
                    raise Exception(f"RTL granted Stream {grant_id}, but Golden Model Notif-FIFO is empty!")
                
                start_macro = st['notif_fifo'].popleft()
                
                is_active = False
                
                if st['current_cfg'] is None:
                    is_active = True
                else:
                    count = st['current_cfg']['apply_count']
                    if count == 0 or st['apply_counter'] < count:
                        is_active = True

                result = {
                    'stream_id': grant_id,
                    'start_macro': start_macro,
                    'window_size': st['window_size'],
                    'mode': st['current_cfg']['mode'] if (st['current_cfg'] and is_active) else 0,
                    'window_id': st['current_window_id'],
                    'payload': st['current_cfg']['payload'] if (st['current_cfg'] and is_active) else 0
                }
                
                self.scoreboard.add_expected(result)
                
                st['apply_counter'] += 1
                st['current_window_id'] += 1
                
            for s in range(self.n_streams):
                if self.dut.cfg_push_i[s].value == 1:
                    val = int(self.dut.cfg_wdata_i[s].value)
                    self.state[s]['cfg_fifo'].append({
                        'mode': (val >> 124) & 0xF,
                        'apply_count': (val >> 112) & 0xFFF,
                        'window_id': (val >> 96) & 0xFFFF,
                        'payload': val & ((1<<96)-1)
                    })
                
                if self.dut.notif_valid_i[s].value == 1:
                    self.state[s]['notif_fifo'].append(int(self.dut.notif_start_macro_i[s].value))


class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.job_valid_o.value and self.dut.job_ready_i.value:
                result = {
                    'stream_id': int(self.dut.job_stream_id_o.value),
                    'start_macro': int(self.dut.job_start_macro_o.value),
                    'window_size': int(self.dut.job_window_size_o.value),
                    'mode': int(self.dut.job_mode_o.value),
                    'window_id': int(self.dut.job_window_id_o.value),
                    'payload': int(self.dut.job_payload_o.value),
                }
                self.scoreboard.add_actual(result)
        
        
class Scoreboard:
    def __init__(self):
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
            
            assert exp['stream_id'] == act['stream_id'], f"Stream ID mismatch: expected {exp['stream_id']}, got {act['stream_id']}"
            assert exp['start_macro'] == act['start_macro'], f"Start Macro mismatch: expected {exp['start_macro']}, got {act['start_macro']}"
            assert exp['window_size'] == act['window_size'], f"Window Size mismatch: expected {exp['window_size']}, got {act['window_size']}"
            assert exp['window_id'] == act['window_id'], f"Window ID mismatch: expected {exp['window_id']}, got {act['window_id']}"
            assert exp['mode'] == act['mode'], f"Mode mismatch: expected {exp['mode']}, got {act['mode']}"  
            assert exp['payload'] == act['payload'], f"Payload mismatch: expected {exp['payload']}, got {act['payload']}"   
            
    def clear(self):
        while not self.expected_q.empty():
            self.expected_q.get_nowait()
        while not self.actual_q.empty():
            self.actual_q.get_nowait()
            
    async def run(self):
        await self.compare()     
        
        
@cocotb.test()
async def test_job_manager_crv(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(dut.N_STREAMS.value)
    scoreboard = Scoreboard()
    golden_model = GoldenModel(dut, scoreboard, n_streams, int(dut.FIFO_DEPTH.value))
    driver = JobManagerDriver(dut, n_streams)
    output_monitor = OutputMonitor(dut, scoreboard)
    
    
    cocotb.start_soon(scoreboard.run())
    cocotb.start_soon(output_monitor.monitor())
    cocotb.start_soon(golden_model.run())
    
    NUM_CYCLES = 100
    for _ in range(NUM_CYCLES):
        golden_model.reset()
        scoreboard.clear()
        await driver.reset()
        
        for stream_id in range(n_streams):
            dut.window_size_i[stream_id].value = rnd.getrandbits(32)

        
        for _ in range(100):
            for stream_id in range(n_streams):
                st = golden_model.state[stream_id]

                if rnd.random() < 0.4 and len(st['notif_fifo']) < golden_model.fifo_depth:
                    start_macro = rnd.randint(0, dut.M_MACROS.value - 1)
                    await driver.send_notification(stream_id, start_macro)
                    
                    
                if rnd.random() < 0.2 and len(st['cfg_fifo']) < golden_model.fifo_depth:
                    pl = rnd.getrandbits(96)
                    
                    cfg = {
                        "mode": rnd.getrandbits(4),
                        "apply_count": rnd.randint(0, 16),
                        "window_id": JobManagerDriver.get_rnd_window_id(st['current_window_id']),
                        "payload": pl,
                    }
                    
                    await driver.send_configuration(stream_id, cfg)
            
            await RisingEdge(dut.clk_i)
            
            for s in range(n_streams):
                dut.notif_valid_i[s].value = 0
                dut.cfg_push_i[s].value = 0
            
            dut.job_ready_i.value = rnd.randint(0, 1)
            
        # Drain remaining jobs
        dut.job_ready_i.value = 1
        
        while True:
            await RisingEdge(dut.clk_i)
            if int(dut.job_valid_o.value) == 0 and \
               int(dut.dut.us_job_valid.value) == 0:
                await ClockCycles(dut.clk_i, 2)
                break
            
    await ClockCycles(dut.clk_i, 10)
        