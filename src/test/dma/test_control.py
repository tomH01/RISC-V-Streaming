from typing import Dict

import cocotb
import random as rnd

from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge
from cocotb.clock import Clock


class ControlDriver:
    def __init__(self, dut):
        self.dut = dut
        self.apb = APBDriver(dut)
        
        self.n_streams = dut.N_STREAMS.value
        self.m_macros = dut.M_MACROS.value      
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def send_ingress_config(self, config_type, data, stream_id=None):        
        stream_base = 0x1000 + stream_id * 0x40 if stream_id is not None else 0
        
        match config_type:
            case "start_macro":
                addr = stream_base + 0x00
            case "window_size":
                addr = stream_base + 0x04
            case "stream_en":
                addr = stream_base + 0x08
            case "topology":
                key, value = data.popitem()
                addr = 0x2000 + (key // 2) * 0x4
                data = value
                
        await self.apb.apb_write(addr, data)

    async def send_egress_config(self, stream_id, idx, data):
        base = 0x1000
        stride = 0x40
        offset = 0x10 + 0x4 * idx
        addr = base + stream_id * stride + offset
        
        await self.apb.apb_write(addr, data)
        

class APBDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 0
        self.dut.paddr_i.value = 0
        self.dut.psel_i.value = 0
        self.dut.pwdata_i.value = 0
        
    async def apb_write(self, addr, data):
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 1
        self.dut.paddr_i.value = addr
        self.dut.psel_i.value = 1
        self.dut.pwdata_i.value = data
        await RisingEdge(self.dut.clk_i)
            
        self.dut.penable_i.value = 1
        await RisingEdge(self.dut.clk_i)

        self.dut.psel_i.value = 0
        self.dut.penable_i.value = 0
        
        
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
        

@cocotb.test()
async def test_ingress_control(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(dut.N_STREAMS.value)
    m_macros = int(dut.M_MACROS.value)
    macro_depth = int(dut.MACRO_DEPTH.value)
    
    driver = ControlDriver(dut)
    
    await driver.reset()
    
    randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        configs = randomizer.generate_configs()
        total_config = {"topology": {}}
        
        for stream_idx, cfg in configs.items():    
            total_config[stream_idx] = {"stream_en": rnd.choice([0, 1]),
                                        "window_size": cfg["window_size"],
                                        "start_macro": cfg["start_macro"]}
            total_config["topology"] |= cfg["topology"]
        
        for stream_idx, cfg in total_config.items():
            if stream_idx == "topology":
                continue
            
            await driver.send_ingress_config("stream_en", cfg["stream_en"], stream_idx)
            await ReadOnly()
            assert dut.stream_en_o[stream_idx].value == cfg["stream_en"], f"Expected stream_en_o[{stream_idx}] to be {cfg['stream_en']}, got: {dut.stream_en_o[stream_idx].value}"
            await FallingEdge(dut.clk_i)
            
            await driver.send_ingress_config("window_size", cfg["window_size"], stream_idx)
            await ReadOnly()
            assert dut.window_size_o[stream_idx].value == cfg["window_size"], f"Expected window_size_o[{stream_idx}] to be {cfg['window_size']}, got: {dut.window_size_o[stream_idx].value}"
            await FallingEdge(dut.clk_i)
            
            await driver.send_ingress_config("start_macro", cfg["start_macro"], stream_idx)
            await ReadOnly()
            assert dut.start_macro_o[stream_idx].value == cfg["start_macro"], f"Expected start_macro_o[{stream_idx}] to be {cfg['start_macro']}, got: {dut.start_macro_o[stream_idx].value}"
            await FallingEdge(dut.clk_i)
                
        for i in range(0, m_macros, 2):
            lower_macro = total_config["topology"].get(i, None)
            upper_macro = total_config["topology"].get(i + 1, None)
            
            if lower_macro is None or upper_macro is None:
                continue
            
            data = {i: (upper_macro << 16) | lower_macro}
            
            await driver.send_ingress_config("topology", data)
            await ReadOnly()
            assert int(dut.next_pointer_o[i].value) == lower_macro, f"Expected next_pointer_o[{i}] to be {lower_macro}, got: {int(dut.next_pointer_o[i].value)}"
            assert int(dut.next_pointer_o[i + 1].value) == upper_macro, f"Expected next_pointer_o[{i+1}] to be {upper_macro}, got: {int(dut.next_pointer_o[i + 1].value)}"
            await FallingEdge(dut.clk_i)

            
@cocotb.test()
async def test_egress_control(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(dut.N_STREAMS.value)
    
    driver = ControlDriver(dut)
    
    await driver.reset()
    
    config = {i: [0, 0, 0] for i in range(n_streams)}
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        idx = rnd.randint(0, 2)
        stream_id = rnd.randint(0, n_streams - 1)
        rand_value = rnd.getrandbits(32)
        config[stream_id][idx] = rand_value
        
        await driver.send_egress_config(stream_id, idx, rand_value)
        await ReadOnly()
        
        if idx == 2:            
            assert int(dut.cfg_push_o[stream_id].value) == 1, f"Expected push signal to be asserted for stream {stream_id}, got: {dut.cfg_push_o[stream_id].value}"
            expected_wdata = int((config[stream_id][2] << 64) | (config[stream_id][1] << 32) | config[stream_id][0])
            assert int(dut.cfg_wdata_o[stream_id].value) == expected_wdata, f"Expected wdata: {expected_wdata}, got: {int(dut.cfg_wdata_o[stream_id].value)}"
        else:
            assert int(dut.cfg_push_o[stream_id].value) == 0, f"Expected push signal to be deasserted for stream {stream_id}, got: {dut.cfg_push_o[stream_id].value}"
        await FallingEdge(dut.clk_i)