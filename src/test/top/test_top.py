import os

import cocotb
import random as rnd
import numpy as np
import math

from pathlib import Path
from collections import deque

from cocotb.queue import Queue
from cocotb.triggers import ClockCycles, Edge, RisingEdge, FallingEdge, ReadOnly, NextTimeStep
from cocotb.clock import Clock

from config_randomizer import ConfigRandomizer

from addr_generator_models import Mode

from control_driver import ControlDriver
from base_driver import BaseDriver
from dma_driver import DMAInterleavedDriver

from data_drivers import OBIDriver
from sensor_set import SensorSet
from utils.python.cocotb import get_design_parameters
from cpu_state import CPUOp

params = get_design_parameters()    


class TopDriver(BaseDriver):
    def __init__(self, dut, sensor_set):
        self.dut = dut
        self.sensor_set = sensor_set
        
        self.ctrl_driver = ControlDriver(dut, driver_protocol="apb")
        self.data_driver = OBIDriver(dut)
        self.dma_driver = DMAInterleavedDriver(dut, self.ctrl_driver, self.data_driver, sensor_set)
        
        self._init_signals()
        
    def _init_signals(self):
        self.dut.data_req_i.value = 0
        self.dut.data_addr_i.value = 0  

@cocotb.test()
async def test_dma_top(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    
    n_streams = int(params["N_STREAMS"])
    m_macros = int(params["M_MACROS"])
    macro_depth = int(params["MACRO_DEPTH"])
    w_workers = int(params["W_WORKERS"])
    data_width = int(params["DATA_WIDTH"])
    b_banks = int(params["B_BANKS"])
    bank_depth = int(params["BANK_DEPTH"])
    data_width_b = data_width // 8
    sram_size_b = b_banks * bank_depth * data_width_b
    
    sensor_set = SensorSet(n_streams, m_macros, macro_depth)
    sensor_set.import_streams("/local/hageltom/teda/bottles/risc-v-streaming/src/test/use_case/w223_l2.csv")
     
    driver = TopDriver(dut, sensor_set)
    ctrl_driver = driver.ctrl_driver
    data_driver = driver.data_driver
    dma_driver = driver.dma_driver
    
    await driver.reset()
    
    configs, topology = sensor_set.generate_configs(verbose=True)
    
    await dma_driver.setup_ingress_cfg(configs, topology)        
    await dma_driver.setup_global_cfg(bank_base=0)
    
    for stream in sensor_set.streams:
        stream.set_fine_tiling_config()
        await dma_driver.send_egress_cfg(
            stream_id=stream.id, 
            counts=stream.counts,
            strides=stream.strides,
            mode=Mode.STRIDED,
            window_id=0
        )

    active_exec_pipeline = []
    pending_reads = []
    
    num_reads = 0    
    trials = 0
    
    NUM_WINDOWS = 100
    MAX_CYCLES = 300000
    for cycle in range(MAX_CYCLES):
        if cycle % 100000 == 0:
            print(f"Cycle {cycle}")
        
        await ReadOnly()
        
        is_stalled = dut.data_req_i.value == 1 and dut.data_gnt_o.value == 0
        
        finished_execs = [exec for exec in active_exec_pipeline if exec[0] == 0]
        active_exec_pipeline = [(cycle - 1, stream_id, ptr) for cycle, stream_id, ptr in active_exec_pipeline if cycle > 0]
        
        for exec in finished_execs:
            _, stream_id, cpu_done_ptr = exec
            stream = sensor_set.streams[stream_id]
            #print(f"Cycle {cycle}: Stream {stream_id} completed execution, CPU done ptr: {cpu_done_ptr}")
            for job in stream.jobs:
                expected_end = (job['start'] + job['size'] - data_width_b) % dma_driver.sram_size_b
                actual_done = cpu_done_ptr

                if not job['exec'] and expected_end == actual_done:
                    job['exec'] = True
                    dma_driver.agu_done_ptrs[stream_id] = -1
                    print(f"Cycle {cycle}: Stream {stream_id} completed job starting at {job['start']} with size {job['size']}")
                    break
            
            dma_driver.update_cpu_done_ptr()
            
        if int(dut.data_r_valid_o.value) == 1:
            assert len(pending_reads) > 0, "Data valid without pending read existing"
            state, meta_data = pending_reads.pop(0)
            data = int(dut.data_r_rdata_o.value)
            
            match state:
                case CPUOp.READ_FIFO:
                    print(f"Cycle {cycle}: Read FIFO data: {data}")
                    stream_id, size = dma_driver.decode_dispatch_data(data)
                    sensor_set.streams[stream_id].jobs.append({
                        'start': dma_driver.alloc_ptr,
                        'size': size * data_width_b,
                        'progress': 0, 
                        'exec': False
                    })
                    dma_driver.alloc_ptr = (dma_driver.alloc_ptr + size * dma_driver.data_width_b) % dma_driver.sram_size_b
                    print(f"Cycle {cycle}: Dispatched job for stream {stream_id}, size: {size}, alloc_ptr: {dma_driver.alloc_ptr}")  
                
                case CPUOp.READ_AGU_DONE_PTR:
                    stream_id = meta_data
                    dma_driver.agu_done_ptrs[stream_id] = data
                    #print(f"Cycle {cycle}: Read AGU Done Ptr for stream {stream_id}: {data}")
                    
                case CPUOp.READ_DATA:
                    addr = meta_data
                    stream = sensor_set.insert_data(addr, data)
                    exec = stream.handle_collection()
                    if exec is not None:
                        active_exec_pipeline.append(exec)
                    num_reads += 1
                    #print(f"Cycle {cycle}: Read data for stream {stream.id} at addr {addr}, data: {data} ({num_reads})")

        # Next State
        if (dut.job_dispatched_o.value == 1):
            dma_driver.dispatch_fifo_fill += 1
            dma_driver.cpu_state = CPUOp.READ_FIFO
        elif dma_driver.cpu_state == CPUOp.READ_FIFO:
            if dma_driver.dispatch_fifo_fill > 0:
                dma_driver.cpu_state = CPUOp.READ_FIFO
            else:
                dma_driver.cpu_state = CPUOp.READ_AGU_DONE_PTR
        else: 
            dma_driver.set_next_state(pending_reads)  
        
        await RisingEdge(dut.clk_i)
        
        if is_stalled:
            continue

        data_driver.clear_bus()
                
        match dma_driver.cpu_state:
            case CPUOp.READ_FIFO:
                dma_driver.dispatch_fifo_fill -= 1
                read_meta = dma_driver.read_fifo_top_init()
                pending_reads.append(read_meta)
                
            case CPUOp.READ_AGU_DONE_PTR:
                stream_ids = [s.id for s in sensor_set.streams if len(s.jobs) > 0]
                if len(stream_ids) > 0:
                    stream_id = rnd.choice(stream_ids) 
                    
                    read_meta = dma_driver.read_agu_done_ptr_init(stream_id)
                    pending_reads.append(read_meta)
                    
            case CPUOp.READ_DATA:
                avail_streams = list(dma_driver.get_read_spaces()[0].keys())
                collecting_streams = [s for s in sensor_set.streams 
                                      if s.id in avail_streams and len(s.data_map) < s.collection_size]
                if collecting_streams:
                    stream = rnd.choice(collecting_streams)
                    job = next((j for j in stream.jobs if j['size'] != j['progress']), None)
                    if job is None:
                        continue
                    addr = (job['start'] + job['progress']) % dma_driver.sram_size_b
                    job['progress'] += data_width_b
                    stream.data_map[addr] = -1
                    read_meta = dma_driver.data_driver.read_init(addr)    
                    pending_reads.append(read_meta)    
                    
            case CPUOp.WRITE_CPU_DONE_PTR:
                await dma_driver.write_cpu_done_ptr(dma_driver.cpu_done_ptr)
                #print(f"Cycle {cycle}: Wrote CPU Done Ptr: {dma_driver.cpu_done_ptr}")
                
    await dma_driver.toggle_dma_enable(False)
    print(await ctrl_driver.fetch_all_perf_counters())
                    
    