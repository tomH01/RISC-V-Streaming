from abc import abstractmethod

import cocotb
from cocotb.triggers import RisingEdge

from addr_generator_models import Mode, StridedGeneratorModel

from base_driver import BaseDriver

from cpu_state import CPUOp

from utils.python.cocotb import get_design_parameters
params = get_design_parameters()


class DMADriver(BaseDriver):    
    def __init__(self, dut, ctrl_driver, data_driver, sensor_set):
        self.dut = dut
        self.ctrl_driver = ctrl_driver
        self.data_driver = data_driver
        
        self.n_streams = int(params["N_STREAMS"])
        self.m_macros = int(params["M_MACROS"])
        self.data_width = int(params["DATA_WIDTH"])
        self.data_width_b = self.data_width // 8
        self.b_banks = int(params["B_BANKS"])
        self.bank_depth = int(params["BANK_DEPTH"])
        self.stride_width = int(params["STRIDE_WIDTH"])
        self.count_width = int(params["COUNT_WIDTH"])
        self.num_axes = int(params["NUM_AXES"])
        self.sram_size_b = self.b_banks * self.bank_depth * self.data_width_b
        
        self.sensor_set = sensor_set
        
        self.strided_addr_gen = StridedGeneratorModel(self.count_width, self.stride_width, self.num_axes)
        
    async def setup_ingress_cfg(self, configs, topology):
        await self._send_topology_cfg(topology)
        
        for stream_id, cfg in configs.items():
            await self._send_stream_cfg(stream_id, cfg)
            
    async def setup_global_cfg(self, bank_base):
        await self.ctrl_driver.send_global_config("bank_base", bank_base)
        self._init_pointers(bank_base)
        await RisingEdge(self.dut.clk_i)
        await self.toggle_dma_enable(True) 
            
    async def toggle_dma_enable(self, enable):
        await self.ctrl_driver.send_global_config("dma_enable", self.ctrl_driver.get_enable(enable))
        
    async def activate_streams(self, configs):
        for stream_id in configs.keys():
            await self._activate_stream(stream_id)     
            
    async def send_egress_cfg(self, stream_id, counts, strides, mode=Mode.LINEAR, apply_count=0, window_id=0):
        payload = self.strided_addr_gen.pack_payload(strides, counts)
        
        cfg_val = (
            ((mode & 0xF) << 124) |
            ((apply_count & 0xFFF) << 112) |
            ((window_id & 0xFFFF) << 96) |
            (payload & ((1 << 96) - 1))
        )
        
        for idx in range(4):
            shift_amount = (3 - idx) * 32
            data = (cfg_val >> shift_amount) & 0xFFFFFFFF
            await self.ctrl_driver.send_egress_config(stream_id, idx, data)
    
    async def _send_stream_cfg(self, stream_id, cfg):
        await self.ctrl_driver.send_ingress_config("start_macro", cfg["start_macro"], stream_id)
        await self.ctrl_driver.send_ingress_config("window_size", cfg["window_size"], stream_id)
        await self.ctrl_driver.send_stream_interval(stream_id, cfg["interval"])
        
    async def _send_topology_cfg(self, topology):
        for i in range(0, self.m_macros, 2):
            await self.ctrl_driver.send_topology_pair(i, topology)
        
    async def _activate_stream(self, stream_id):
        await self.ctrl_driver.send_ingress_config("stream_en", 1, stream_id)  
    
    @abstractmethod
    def _init_pointers(self, bank_base):
        pass
            
            
class DMAInterleavedDriver(DMADriver):
    META_BASE = 0x0010_0000
    CPU_DONE_PTR = 0x80
    FIFO_TOP = 0x84
    
    def __init__(self, dut, ctrl_driver, data_driver, sensor_set):
        super().__init__(dut, ctrl_driver, data_driver, sensor_set)
        
        self.dispatch_fifo_fill = 0
        self.alloc_ptr = 0
        
        self.cpu_done_ptr = 0
        self.written_cpu_done_ptr = 0
        
        self.agu_done_ptrs = [0] * self.n_streams
        self.cpu_state = CPUOp.NOP
        
    async def read_agu_done_ptr(self, stream_id):
        addr = self.META_BASE + (stream_id * self.data_width_b)
        return await self.data_driver.read(addr)
    
    def read_agu_done_ptr_init(self, stream_id):
        addr = self.META_BASE + (stream_id * self.data_width_b)
        self.data_driver.read_init(addr)
        return (CPUOp.READ_AGU_DONE_PTR, stream_id)

    def write_cpu_done_ptr(self, value):
        addr = self.META_BASE + self.CPU_DONE_PTR
        self.written_cpu_done_ptr = value
        self.data_driver.write(addr, value)
        
    async def read_fifo_top(self):
        addr = self.META_BASE + self.FIFO_TOP
        return await self.data_driver.read(addr)
    
    def read_fifo_top_init(self):
        addr = self.META_BASE + self.FIFO_TOP
        self.data_driver.read_init(addr)
        return (CPUOp.READ_FIFO, addr)
    
    def set_next_state(self, pending_reads):
        avail_space = DMAInterleavedDriver.get_ring_dist(self.alloc_ptr, self.written_cpu_done_ptr, self.sram_size_b)
        unwritter_ptr = self.cpu_done_ptr != self.written_cpu_done_ptr
        
        if unwritter_ptr and avail_space != 0 and avail_space <= self.sram_size_b // 4:
            print(f"Available space is {avail_space}, writing CPU done pointer")
            self.cpu_state = CPUOp.WRITE_CPU_DONE_PTR
            return

        read_spaces, close_read_spaces = self.get_read_spaces()
        
        pipeline_top = pending_reads[-1] if pending_reads else None
        is_agu_ptr_read = pipeline_top is not None and pipeline_top[0] == CPUOp.READ_AGU_DONE_PTR
        
        effective_space = read_spaces if is_agu_ptr_read else close_read_spaces
        
        self.cpu_state = CPUOp.READ_DATA if effective_space else CPUOp.READ_AGU_DONE_PTR
            
    def update_cpu_done_ptr(self):
        ptrs = []
        for stream in self.sensor_set.streams:
            for job in stream.jobs:
                if not job['exec']:
                    ptrs.append(job['start'])
                    break

        if ptrs:
            self.cpu_done_ptr = max(ptrs, key=lambda ptr: DMAInterleavedDriver.get_ring_dist(ptr, self.alloc_ptr, self.sram_size_b))
            
    def get_read_spaces(self):
        read_spaces = {}
        close_read_spaces = {}
        for stream_id, stream in enumerate(self.sensor_set.streams):
            if len(stream.jobs) > 0:
                job = next((j for j in stream.jobs if j['size'] != j['progress']), None)
                if job is None:
                    continue
                
                read_space = self._get_read_space(stream_id, job)
                if read_space > 0:
                    read_spaces[stream_id] = read_space
                if read_space > self.data_width_b:
                    close_read_spaces[stream_id] = read_space
        return read_spaces, close_read_spaces
    
    def decode_dispatch_data(self, data):
        stream_id = (data >> 27) & 0x1F
        size = data & 0x7FF_FFFF
        return stream_id, size

    @staticmethod
    def get_ring_dist(ptr_a, ptr_b, ring_size):
        return (ptr_b - ptr_a) % ring_size

    def _get_read_space(self, stream_id, job):
        agu_ptr = self.agu_done_ptrs[stream_id]
        
        if agu_ptr == -1:
            return 0
        
        agu_dist = DMAInterleavedDriver.get_ring_dist(job['start'], agu_ptr, self.sram_size_b)
        if agu_dist > self.sram_size_b // 2:
            return 0
        if agu_dist <= job['progress']:
            return 0
        return agu_dist - job['progress']
    
    def _init_pointers(self, bank_base):
        self.cpu_done_ptr = bank_base
        self.written_cpu_done_ptr = bank_base
        self.alloc_ptr = bank_base
        for i in range(self.n_streams):
            self.agu_done_ptrs[i] = -1
        

class DMABlockWiseDriver(DMADriver):
    def __init__(self, dut, ctrl_driver, data_driver, sensor_set, header_size_b):
        super().__init__(dut, ctrl_driver, data_driver, sensor_set)
        
        self.bank_base = 0
        self.header_size_b = header_size_b
        self.bank_queue = []
        self.current_bank = None
        self.completed_banks = []
        
        self.state = CPUOp.NOP
        self.pending_reads = []
        
        self.cycle = 0
        
    def _init_pointers(self, bank_base):
        self.bank_base = bank_base
        
    async def setup_global_cfg(self, bank_base):
        await self.ctrl_driver.send_global_config("bank_base", bank_base)
        await self.ctrl_driver.send_global_config("header_size", self.header_size_b)
        self._init_pointers(bank_base)
        await RisingEdge(self.dut.clk_i)
        await self.toggle_dma_enable(True)
        
    def decode_dispatch_data(self, data):
        stream_id = (data >>16) & 0xFFFF
        block_id = data & 0xFFFF
        return stream_id, block_id
        
    def update_bank_queue(self):
        if int(self.dut.bank_full_o.value) != 0:
            print(f"Cycle {self.cycle}: Bank full signal: {self.dut.bank_full_o.value}")
            self.bank_queue.extend(b for b in range(self.b_banks) if self.dut.bank_full_o[b].value == 1) 
        
    def handle_read_response(self):
        cb = self.current_bank
        
        if int(self.dut.data_r_valid_o.value) == 1:
            assert len(self.pending_reads) > 0, "Data valid without pending read existing"
        else:
            return
    
        state, meta_data = self.pending_reads.pop(0)
        data = int(self.dut.data_r_rdata_o.value)
    
        assert cb is not None, "Received read response without an active bank"
        
        
        match state:
            case CPUOp.READ_NUM_BLOCKS:
                cb["num_blocks"] = data
                if data == 0:
                    self.state = CPUOp.WRITE_RELEASE_BANK
                    
            case CPUOp.READ_BLOCK_ID:
                    cb["temp_block_id"] = data
                
            case CPUOp.READ_BLOCK_SIZE:
                block_id = cb["temp_block_id"]
                stream_id, block_id = self.decode_dispatch_data(block_id)
                block_size_b = data
                
                cb["blocks"].append([stream_id, block_id, block_size_b, 0, 0])
                cb["temp_block_id"] = None
            
            case CPUOp.READ_DATA:               
                block_id = next((i for i, b in enumerate(cb["blocks"]) if b[2] != b[3]), None)
                
                if block_id is not None:
                    cb["blocks"][block_id][3] += self.data_width_b
            
            case _:
                raise ValueError(f"Unexpected state {state} in read response handling")
        
    def get_next_state(self):
        if self.state == CPUOp.WRITE_RELEASE_BANK:
            return
        
        if self.current_bank is None and len(self.bank_queue) > 0:
            self._fetch_next_bank()
            
        cb = self.current_bank
        
        if cb is None:
            self.state = CPUOp.NOP
            return
        
        if cb["num_blocks"] is None:
            if cb["num_blocks_requested"]:
                self.state = CPUOp.NOP
            else:
                self.state = CPUOp.READ_NUM_BLOCKS
                cb["num_blocks_requested"] = True
                
        elif self.state == CPUOp.READ_BLOCK_ID:
            self.state = CPUOp.READ_BLOCK_SIZE
            
        elif cb["req_blocks"] < cb["num_blocks"]:
            self.state = CPUOp.READ_BLOCK_ID
            
        elif len(cb["blocks"]) < cb["num_blocks"]:
            self.state = CPUOp.NOP
                
        elif any(b[4] < b[2] for b in cb["blocks"]):
            self.state = CPUOp.READ_DATA
        
        elif any(b[3] < b[2] for b in cb["blocks"]):
            self.state = CPUOp.NOP
            
        else:
            if cb["exec_delay"] is None:
                stream_id = cb["blocks"][-1][0]
                cb["exec_delay"] = self.sensor_set.streams[stream_id].exec_time
                
            if cb["exec_delay"] > 0:
                cb["exec_delay"] -= 1
                self.state = CPUOp.NOP
            else:
                self.state = CPUOp.WRITE_RELEASE_BANK
            
    async def issue_request(self, cycle):
        cb = self.current_bank
        
        if cb is None or self.state == CPUOp.NOP:
            return
        
        block_num = cb["req_blocks"]
        
        match self.state:
            case CPUOp.READ_NUM_BLOCKS:
                self._read_num_blocks_init()
                self.pending_reads.append((CPUOp.READ_NUM_BLOCKS, None))
                
            case CPUOp.READ_BLOCK_ID:
                self._read_block_id_init(block_num)
                self.pending_reads.append((CPUOp.READ_BLOCK_ID, block_num))
                
            case CPUOp.READ_BLOCK_SIZE:
                self._read_block_size_init(block_num)
                self.pending_reads.append((CPUOp.READ_BLOCK_SIZE, block_num))
                cb["req_blocks"] += 1
                
            case CPUOp.READ_DATA:
                req_block_id = next(i for i, b in enumerate(cb["blocks"]) if b[4] < b[2])
                cb["blocks"][req_block_id][4] += self.data_width_b
                
                self.data_driver.read_init(cb["bank_offset"])
                cb["bank_offset"] += self.data_width_b 
                self.pending_reads.append((CPUOp.READ_DATA, None))               
                
            case CPUOp.WRITE_RELEASE_BANK:
                await self._write_release_bank()
                self.current_bank = None
                self.state = CPUOp.NOP
                
                bank_content = [(b[0], b[2]) for b in cb["blocks"]]
                print(f"Cycle {self.cycle}: Completed bank {cb['id']} with {len(bank_content)} blocks: {bank_content}")
                
    def _fetch_next_bank(self):
        bank_id = self.bank_queue.pop(0)
        self.current_bank = {
            "id": bank_id,
            "num_blocks": None,
            "num_blocks_requested": False,
            "req_blocks": 0,
            "temp_block_id": None,
            "blocks": [],
            "exec_delay": None,
            "bank_offset": self._get_bank_base_addr(bank_id) + self.header_size_b,
        }
    
    def _read_num_blocks_init(self):
        assert self.current_bank is not None, "No current bank to read number of blocks from"
        bank_base = self._get_bank_base_addr(self.current_bank["id"])
        addr = bank_base
        self.data_driver.read_init(addr)
        
    def _read_block_id_init(self, block_num):
        assert self.current_bank is not None, "No current bank to read block ID from"
        bank_base = self._get_bank_base_addr(self.current_bank["id"])
        addr = bank_base + self.data_width_b + (block_num * 2 * self.data_width_b)
        self.data_driver.read_init(addr)
        
    def _read_block_size_init(self, block_num):
        assert self.current_bank is not None, "No current bank to read block size from"
        bank_base = self._get_bank_base_addr(self.current_bank["id"])
        addr = bank_base + self.data_width_b + (block_num * 2 * self.data_width_b) + self.data_width_b
        self.data_driver.read_init(addr)
          
    async def _write_release_bank(self):
        assert self.current_bank is not None, "No current bank to release"
        data = 1 << self.current_bank["id"]
        await self.ctrl_driver.send_global_config("release_bank", data)
    
    def _get_bank_base_addr(self, bank_id):
        return self.bank_base + (bank_id * self.bank_depth * self.data_width_b)
    