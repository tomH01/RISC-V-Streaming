import random as rnd

from typing import Dict

import cocotb

from cocotb.queue import Queue
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


class IngressTopDriver:
    def __init__(self, dut, n_streams, m_macros):
        self.dut = dut
        self.n_streams = n_streams
        self.m_macros = m_macros
        
        for s in range(n_streams):
            self.dut.stream_data_i[s].value = 0
            self.dut.stream_valid_i[s].value = 0
            self.dut.cfg_window_size_i[s].value = 0
            self.dut.cfg_start_macro_i[s].value = 0
        
        for m in range(m_macros):
            self.dut.cfg_next_pointer_i[m].value = 0  
            self.dut.bp_gnt_i[m].value = 1
        
        self.dut.cfg_stream_en_i.value = 0        
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def configure_stream(self, stream_idx, window_size, start_macro, topology):
        self.dut.cfg_stream_en_i[stream_idx].value = 1
        self.dut.cfg_window_size_i[stream_idx].value = window_size
        self.dut.cfg_start_macro_i[stream_idx].value = start_macro
        for current_m, next_m in topology.items():
            self.dut.cfg_next_pointer_i[current_m].value = next_m
        await RisingEdge(self.dut.clk_i)
            
    async def send_words(self, stream_idx, nb_words, delay_prob=0.0):
        for word in range(0xFFFFFFFF, 0xFFFFFFFF-nb_words, -1):
            while rnd.random() < delay_prob:
                self.dut.stream_valid_i[stream_idx].value = 0
                await RisingEdge(self.dut.clk_i)
                
            self.dut.stream_valid_i[stream_idx].value = 1
            self.dut.stream_data_i[stream_idx].value = word
            
            await RisingEdge(self.dut.clk_i)

        self.dut.stream_valid_i[stream_idx].value = 0
            

class ConfigRandomizer:
    def __init__(self, n_streams, m_macros, macro_depth):
        self.n_streams = n_streams
        self.m_macros = m_macros
        self.macro_depth = macro_depth
    
    def generate_configs(self) -> Dict[int, Dict]:
        configs = {}
        
        available_macros = list(range(self.m_macros))
        rnd.shuffle(available_macros)    
        
        nb_active_streams = rnd.randint(1, self.n_streams)
            
        active_stream_ids = rnd.sample(range(self.n_streams), nb_active_streams)
        window_sizes, macros_per_window_list = self._generate_window_sizes(nb_active_streams)
        
        for i, stream_idx in enumerate(active_stream_ids):
            required_left_macros = 0
            for s in range(i + 1, len(active_stream_ids)):
                required_left_macros += macros_per_window_list[s] * 2
                    
            max_macros_to_allocate = len(available_macros) - required_left_macros
            multiplier = rnd.randint(2, max_macros_to_allocate // macros_per_window_list[i])
            num_allocated_macros = multiplier * macros_per_window_list[i]
            
            macros = [available_macros.pop() for _ in range(num_allocated_macros)]
            
            topology = {}
            for j in range(num_allocated_macros):
                current_macro = macros[j]
                next_macro = macros[(j + 1) % num_allocated_macros]
                topology[current_macro] = next_macro
                
            configs[stream_idx] = {
                'window_size': window_sizes[i],
                'start_macro': macros[0],
                'topology': topology
            }
        return configs          
                
    def _generate_window_sizes(self, nb_active_streams):
        pool = self.m_macros
        window_sizes = []
        macros_per_window_list = []
        
        for i in range(nb_active_streams):
            streams_left = nb_active_streams - i - 1
            reserved = streams_left * 2
            
            while True:
                window_size = rnd.randint(1, 2 * self.macro_depth)
                macros_per_window = (window_size - 1) // self.macro_depth + 1
                
                if macros_per_window * 2 <= (pool - reserved):
                    window_sizes.append(window_size)
                    macros_per_window_list.append(macros_per_window)
                    pool -= macros_per_window * 2
                    break
                    
        return window_sizes, macros_per_window_list
                

class InputMonitor:
    def __init__(self, dut, stream_idx, golden_model, scoreboard):
        self.dut = dut
        self.stream_idx = stream_idx
        self.golden_model = golden_model
        self.scoreboard = scoreboard

    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)            
            await ReadOnly()
            
            if self.dut.stream_valid_i[self.stream_idx].value == 1 and self.dut.stream_ready_o[self.stream_idx].value == 1:
                data = self.dut.stream_data_i[self.stream_idx].value.integer
                macro, expected_txn, expected_notif, expected_done_macro = self.golden_model.process_transaction(self.stream_idx, data)
                self.scoreboard.add_expected(macro, expected_txn)
                
                if expected_notif:
                    self.scoreboard.add_expected_notification(self.stream_idx, expected_notif)
                    
                if expected_done_macro:
                    cocotb.start_soon(self.check_delayed_done(expected_done_macro))
                        
    async def check_delayed_done(self, expected_macro):
        await RisingEdge(self.dut.clk_i)
        await ReadOnly()
        
        expected = int(self.dut.bp_done_o[expected_macro].value)
        assert expected == 1, f"Expected done signal for macro {expected_macro} asserted, got {expected}."


class NotificationMonitor:
    def __init__(self, dut, n_streams, scoreboard):
        self.dut = dut
        self.n_streams = n_streams
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()

            if self.dut.notify_valid_o.value.integer > 0:
                for s in range(self.n_streams):
                    if self.dut.notify_valid_o[s].value == 1:
                        notif = {
                            "stream_idx": s,
                            "macro": self.dut.notify_start_macro_o[s].value.integer,
                        }
                        self.scoreboard.add_actual_notification(s, notif)
    

class OutputMonitor:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.scoreboard = scoreboard
        
    async def monitor(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
            
            if self.dut.bp_req_o.value.integer >= 1:
                for macro_idx in range(self.scoreboard.m_macros):
                    if self.dut.bp_req_o[macro_idx].value == 1:
                        actual = {
                            "addr": self.dut.bp_addr_o[macro_idx].value.integer,
                            "wdata": self.dut.bp_wdata_o[macro_idx].value.integer,
                        }
                        self.scoreboard.add_actual(macro_idx, actual)
    

class GoldenModel:
    def __init__(self, n_streams, m_macros, macro_depth):
        self.n_streams = n_streams
        self.m_macros = m_macros
        self.macro_depth = macro_depth
        
        self.config = [{'window_size': 0, 
                        'start_macro': 0, 
                        'topology': {}} for _ in range(self.n_streams)]
        
        self.stream_states = [{'active': False, 
                               'current_macro': None,
                               'macro_word_cnt': 0,
                               'window_cnt': 0,
                               'window_start_macro': None} for _ in range(self.n_streams)]
        
    def configure_stream(self, stream_idx, window_size, start_macro, topology):
        self.config[stream_idx] = {'window_size': window_size, 
                                   'start_macro': start_macro,
                                   'topology': topology}
        
    def activate_stream(self, stream_idx):
        self.stream_states[stream_idx]['active'] = True
        self.stream_states[stream_idx]['current_macro'] = self.config[stream_idx]['start_macro']
        self.stream_states[stream_idx]['macro_word_cnt'] = 0
        self.stream_states[stream_idx]['window_cnt'] = 0
        
    def process_transaction(self, stream_idx: int, data: int):
        config = self.config[stream_idx]
        state = self.stream_states[stream_idx]
        
        expected_macro = state['current_macro']
        expected = {
            "addr": state['macro_word_cnt'], 
            "wdata": data,
        }
        
        if state['window_cnt'] == 0:
            state['window_start_macro'] = state['current_macro']
        
        state['macro_word_cnt'] += 1
        state['window_cnt'] += 1
        
        expected_notification = None
        expected_done_macro = None
        
        if state['window_cnt'] >= config['window_size']:
            expected_notification = {
                "stream_idx": stream_idx,
                "macro": state['window_start_macro'],
            }
            expected_done_macro = state['current_macro']
            
            state['current_macro'] = config['topology'][state['current_macro']]
            state['macro_word_cnt'] = 0
            state['window_cnt'] = 0
            
        elif state['macro_word_cnt'] >= self.macro_depth:
            state['current_macro'] = config['topology'][state['current_macro']]
            state['macro_word_cnt'] = 0   
            
        return expected_macro, expected, expected_notification, expected_done_macro
            
        
class ScoreBoard:
    def __init__(self, m_macros, n_streams, golden_model=None):
        self.m_macros: int = m_macros
        self.n_streams: int = n_streams
        self.golden_model = golden_model

        self.expected_q: Queue = {m: Queue() for m in range(m_macros)}
        self.actual_q: Queue = {m: Queue() for m in range(m_macros)}
        
        self.expected_notif_q: Queue = {s: Queue() for s in range(n_streams)}
        self.actual_notif_q: Queue = {s: Queue() for s in range(n_streams)}

    def add_expected(self, macro_idx, expected):
        self.expected_q[macro_idx].put_nowait(expected)
        
    def add_actual(self, macro_idx, actual):
        self.actual_q[macro_idx].put_nowait(actual)
        
    def add_expected_notification(self, stream_idx, expected):
        self.expected_notif_q[stream_idx].put_nowait(expected)
        
    def add_actual_notification(self, stream_idx, actual):
        self.actual_notif_q[stream_idx].put_nowait(actual)
        
    async def compare_macro(self, macro_idx):
        while True:
            exp = await self.expected_q[macro_idx].get()
            act = await self.actual_q[macro_idx].get()               
            
            assert exp["addr"] == act["addr"], f"Macro {macro_idx}: Expected addr {exp['addr']}, got {act['addr']}"
            assert exp["wdata"] == act["wdata"], f"Macro {macro_idx}: Expected wdata {exp['wdata']}, got {act['wdata']}"
            
    async def compare_notification(self, stream_idx):
        while True:
            exp = await self.expected_notif_q[stream_idx].get()
            act = await self.actual_notif_q[stream_idx].get()  
            
            assert exp["macro"] == act["macro"], f"Notification of Stream {stream_idx}: Expected macro {exp['macro']}, got {act['macro']}"
                         
            
    async def run(self):
        for m in range(self.m_macros):
            cocotb.start_soon(self.compare_macro(m))
            
        for s in range(self.n_streams):
            cocotb.start_soon(self.compare_notification(s))
        
    
@cocotb.test()
async def test_ingress_top_crv(dut):
    rnd.seed(42)  
    
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(dut.N_STREAMS.value)
    m_macros = int(dut.M_MACROS.value)
    macro_depth = int(dut.MACRO_DEPTH.value)
    
    driver = IngressTopDriver(dut, n_streams=n_streams, m_macros=m_macros)
    
    golden_model = GoldenModel(n_streams=n_streams, m_macros=m_macros, macro_depth=macro_depth)
    score_board = ScoreBoard(m_macros=m_macros, n_streams=n_streams, golden_model=golden_model)
    
    config_randomizer = ConfigRandomizer(n_streams=n_streams, m_macros=m_macros, macro_depth=macro_depth)
    
    input_monitors = [InputMonitor(dut, stream_idx=s, golden_model=golden_model, scoreboard=score_board) for s in range(n_streams)]
    output_monitor = OutputMonitor(dut, scoreboard=score_board)
    notif_monitor = NotificationMonitor(dut, n_streams=n_streams, scoreboard=score_board)
    
    await driver.reset()
    
    for im in input_monitors:
        cocotb.start_soon(im.monitor())
    cocotb.start_soon(output_monitor.monitor())
    cocotb.start_soon(score_board.run())
    cocotb.start_soon(notif_monitor.monitor())
    
    NB_RUNS = 100
    for n in range(NB_RUNS):
        await driver.reset()
        
        configs = config_randomizer.generate_configs()
        
        tasks = []
        
        for stream_idx, cfg in configs.items():
            await driver.configure_stream(
                stream_idx, 
                cfg['window_size'],
                cfg['start_macro'],
                cfg['topology']
            )
            
            golden_model.configure_stream(
                stream_idx, 
                cfg['window_size'],
                cfg['start_macro'],
                cfg['topology']
            )
            golden_model.activate_stream(stream_idx)
            
            macros_per_window = (cfg['window_size'] - 1) // macro_depth + 1
            max_words = len(cfg['topology']) / macros_per_window * cfg['window_size']
            
            task = cocotb.start_soon(driver.send_words(
                stream_idx, 
                nb_words=rnd.randint(1, int(max_words)), 
                delay_prob=0.3
            ))
            tasks.append(task)
            
        for t in tasks:
            await t
            
        for _ in range(100):
            await RisingEdge(dut.clk_i)
            
        driver.dut.cfg_stream_en_i.value = 0
        for stream_idx in range(n_streams):
            golden_model.stream_states[stream_idx]['active'] = False
            
        print("Pass run ", n)
            
    for macro in range(m_macros):
        assert score_board.expected_q[macro].empty()
        assert score_board.actual_q[macro].empty()
        
    for stream_idx in range(n_streams):
        assert score_board.expected_notif_q[stream_idx].empty()
        assert score_board.actual_notif_q[stream_idx].empty()
    