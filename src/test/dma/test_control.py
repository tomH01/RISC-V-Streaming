from typing import Dict

import cocotb
import random as rnd

from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer
from control_driver import ControlDriver

from utils.python.cocotb import get_design_parameters
params = get_design_parameters()
        
        
@cocotb.test()
async def test_global_control(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    b_banks = int(params["B_BANKS"])
    
    driver = ControlDriver(dut)

    await driver.reset()
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):    
        dma_enable = rnd.choice([0, 1])
        global_control = driver.get_global_control(dma_enable)    
        await driver.send_global_config("global_ctrl", global_control)
        await ReadOnly()
        assert int(dut.dma_enable_o.value) == dma_enable, f"Expected dma_enable_o to be {dma_enable}, got: {dut.dma_enable_o.value}"
        await FallingEdge(dut.clk_i)
        
        bank_limit_b = rnd.getrandbits(32)
        await driver.send_global_config("bank_limit_b", bank_limit_b)
        await ReadOnly()
        assert int(dut.bank_limit_b_o.value) == bank_limit_b, f"Expected bank_limit_b_o to be {bank_limit_b}, got: {dut.bank_limit_b_o.value}"
        await FallingEdge(dut.clk_i)
        
        bank_base_idx = rnd.randrange(0, b_banks)
        bank_base_value = rnd.getrandbits(32)
        await driver.send_global_config("bank_base", bank_base_value, bank_base_idx)
        await ReadOnly()
        assert int(dut.l2_bank_base_o[bank_base_idx].value) == bank_base_value, f"Expected l2_bank_base_o[{bank_base_idx}] to be {bank_base_value}, got: {dut.l2_bank_base_o[bank_base_idx].value}"
        await FallingEdge(dut.clk_i)   
               
        
@cocotb.test()
async def test_ingress_control(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    
    driver = ControlDriver(dut)
    await driver.reset()
    
    randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        configs, total_topology = randomizer.generate_configs()
        
        for stream_idx, cfg in configs.items():
            stream_en = rnd.choice([0, 1])
            await driver.send_ingress_config("stream_en", stream_en, stream_idx)
            await ReadOnly()
            assert dut.stream_en_o[stream_idx].value == stream_en, f"Expected stream_en_o[{stream_idx}] to be {stream_en}, got: {dut.stream_en_o[stream_idx].value}"
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
            lower_macro = total_topology.get(i, None)
            upper_macro = total_topology.get(i + 1, None)
            
            if lower_macro is None or upper_macro is None:
                continue
            
            await driver.send_topology_pair(i, total_topology)
            
            await ReadOnly()
            
            assert int(dut.next_pointer_o[i].value) == lower_macro, f"Expected next_pointer_o[{i}] to be {lower_macro}, got: {int(dut.next_pointer_o[i].value)}"
            assert int(dut.next_pointer_o[i + 1].value) == upper_macro, f"Expected next_pointer_o[{i+1}] to be {upper_macro}, got: {int(dut.next_pointer_o[i + 1].value)}"
            await FallingEdge(dut.clk_i)

            
@cocotb.test()
async def test_egress_control(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])

    driver = ControlDriver(dut)
    await driver.reset()
    
    config = {i: [0, 0, 0, 0] for i in range(n_streams)}
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        await RisingEdge(dut.clk_i)
        idx = rnd.randint(0, 3)
        stream_id = rnd.randint(0, n_streams - 1)
        rand_value = rnd.getrandbits(32)
        config[stream_id][idx] = rand_value
        
        await driver.send_egress_config(stream_id, idx, rand_value)
        await ReadOnly()
        
        if idx == 3:            
            assert int(dut.cfg_push_o[stream_id].value) == 1, f"Expected push signal to be asserted for stream {stream_id}, got: {dut.cfg_push_o[stream_id].value}"
            expected_wdata = int((config[stream_id][0] << 96) | (config[stream_id][1] << 64) | (config[stream_id][2] << 32) | config[stream_id][3])
            assert int(dut.cfg_wdata_o[stream_id].value) == expected_wdata, f"Expected wdata: {expected_wdata}, got: {int(dut.cfg_wdata_o[stream_id].value)}"
            await RisingEdge(dut.clk_i)
            await ReadOnly()
            assert int(dut.cfg_push_o[stream_id].value) == 0, f"Expected push signal to be deasserted for stream {stream_id} after one cycle, got: {dut.cfg_push_o[stream_id].value}"
        else:
            assert int(dut.cfg_push_o[stream_id].value) == 0, f"Expected push signal to be deasserted for stream {stream_id}, got: {dut.cfg_push_o[stream_id].value}"
        
@cocotb.test()
async def test_stream_interval(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units='ns').start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])

    driver = ControlDriver(dut)
    await driver.reset()
    
    randomizer = ConfigRandomizer(n_streams, m_macros, macro_depth)
    
    NUM_CYCLES = 1000
    for _ in range(NUM_CYCLES):
        await RisingEdge(dut.clk_i)
        configs, _ = randomizer.generate_configs()
        
        for stream_id, cfg in configs.items():
            interval = cfg["interval"]
            
            await driver.send_stream_interval(stream_id, interval)
            
            await ReadOnly()
            assert int(dut.stream_interval_o[stream_id].value) == interval, f"Expected stream_interval_o[{stream_id}] to be {interval}, got: {int(dut.stream_interval_o[stream_id].value)}"
            
            await FallingEdge(dut.clk_i)
            