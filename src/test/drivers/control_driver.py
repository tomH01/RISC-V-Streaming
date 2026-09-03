import cocotb

from cocotb.triggers import RisingEdge

from utils.python.cocotb import get_design_parameters
params = get_design_parameters()


class ControlDriver:
    GLOBAL_BASE = 0x48000000
    STREAM_BASE = 0x48001000
    TOPOLOGY_BASE = 0x48002000
    INTERVAL_BASE = 0x48003000
    PERF_MON_BASE = 0x48004000
    
    # Global Config
    DMA_ENABLE = 0x00
    EGRESS_ENABLE = 0x04
    BANK_BASE = 0x08  
    HEADER_SIZE = 0x0C
    RELEASE_BANK = 0x10
    
    # Stream Config
    INGR_STREAM_STRIDE = 0x20
    
    OFF_START_MACRO = 0x00
    OFF_WINDOW_SIZE = 0x04
    OFF_STREAM_EN = 0x08
    
    OFF_EGRESS_SHADOW_0 = 0x10
    OFF_EGRESS_SHADOW_1 = 0x14
    OFF_EGRESS_SHADOW_2 = 0x18
    OFF_EGRESS_TRIGGER = 0x1C
    
    # Performance Monitor Config
    OFF_SETUP_CNT = 0x00
    OFF_RUN_CNT = 0x04
    OFF_EGR_JOB_HS_CNT = 0x08
    OFF_EGR_JOB_BP_CNT = 0x0C
    OFF_EGR_META_HS_CNT = 0x10
    OFF_EGR_META_BP_CNT = 0x14
    OFF_CPU_L2_HS_CNT = 0x18
    OFF_CPU_L2_BP_CNT = 0x1C
    OFF_CPU_META_HS_CNT = 0x20
    OFF_CPU_META_BP_CNT = 0x24
    
    PERF_STREAM_BASE = 0x100
    PERF_STREAM_STRIDE = 0x08
    OFF_STREAM_INGR_HS_CNT = 0x00
    OFF_STREAM_INGR_BP_CNT = 0x04
    
    PERF_WORKER_BASE = 0x200
    PERF_WORKER_STRIDE = 0x10
    OFF_WORKER_EGR_WKR_BP_HS_CNT = 0x00
    OFF_WORKER_EGR_WKR_BP_BP_CNT = 0x04
    OFF_WORKER_EGR_WKR_BUS_HS_CNT = 0x08 
    OFF_WORKER_EGR_WKR_BUS_BP_CNT = 0x0C
    
    
    def __init__(self, dut, driver_protocol="apb"):
        self.dut = dut
        self.n_streams = int(params["N_STREAMS"])
        self.m_macros = int(params["M_MACROS"])
        self.b_banks = int(params["B_BANKS"])
        self.w_workers = int(params["W_WORKERS"])
        
        if driver_protocol == "apb":
            from ctrl_drivers import APBDriver
            self.driver = APBDriver(dut)
        elif driver_protocol == "axi":
            from ctrl_drivers import AXILiteDriver
            self.driver = AXILiteDriver(dut)
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def send_global_config(self, config_type, data):       
        match config_type:
            case "dma_enable":
                addr = self.GLOBAL_BASE + self.DMA_ENABLE
            case "bank_base":
                addr = self.GLOBAL_BASE + self.BANK_BASE
            case "egress_enable":
                addr = self.GLOBAL_BASE + self.EGRESS_ENABLE
            case "header_size":
                addr = self.GLOBAL_BASE + self.HEADER_SIZE
            case "release_bank":
                addr = self.GLOBAL_BASE + self.RELEASE_BANK
            case _:
                raise ValueError(f"Unknown config type: {config_type}")
                
        await self.driver.write(addr, data)
        
    async def send_ingress_config(self, config_type, data, stream_id):    
        stream_addr = self.STREAM_BASE + stream_id * self.INGR_STREAM_STRIDE
        
        match config_type:
            case "start_macro":
                addr = stream_addr + self.OFF_START_MACRO
            case "window_size":
                addr = stream_addr + self.OFF_WINDOW_SIZE
            case "stream_en":
                addr = stream_addr + self.OFF_STREAM_EN
            case _:
                raise ValueError(f"Unknown config type: {config_type}")
                
        await self.driver.write(addr, data)

    async def send_egress_config(self, stream_id, idx, data):
        offset = self.OFF_EGRESS_SHADOW_0 + 0x4 * idx
        addr = self.STREAM_BASE + stream_id * self.INGR_STREAM_STRIDE + offset
        
        await self.driver.write(addr, data)
        
    async def send_stream_interval(self, stream_id, interval):
        addr = self.INTERVAL_BASE + stream_id * 0x4
        await self.driver.write(addr, interval)
        
    async def send_topology_pair(self, macro_idx, total_topology):
        lower_macro = total_topology.get(macro_idx, macro_idx)
        upper_macro = total_topology.get(macro_idx + 1, macro_idx + 1)
        
        if lower_macro is None or upper_macro is None:
            return
        
        addr = self.TOPOLOGY_BASE + (macro_idx // 2) * 0x4
        packed_data =  (upper_macro << 16) | lower_macro
        
        await self.driver.write(addr, packed_data)
        
    def get_enable(self, enable):
        enable_bit = (int(enable) & 0x1) << 31
        return enable_bit
    
    async def fetch_all_perf_counters(self):
        counters = {}

        global_regs = {
            "PERF_SETUP_CNT": self.OFF_SETUP_CNT,
            "PERF_RUN_CNT": self.OFF_RUN_CNT,
            "PERF_EGR_JOB_HS_CNT": self.OFF_EGR_JOB_HS_CNT,
            "PERF_EGR_JOB_BP_CNT": self.OFF_EGR_JOB_BP_CNT,
            "PERF_EGR_META_HS_CNT": self.OFF_EGR_META_HS_CNT,
            "PERF_EGR_META_BP_CNT": self.OFF_EGR_META_BP_CNT,
            "PERF_CPU_L2_HS_CNT": self.OFF_CPU_L2_HS_CNT,
            "PERF_CPU_L2_BP_CNT": self.OFF_CPU_L2_BP_CNT,
            "PERF_CPU_META_HS_CNT": self.OFF_CPU_META_HS_CNT,
            "PERF_CPU_META_BP_CNT": self.OFF_CPU_META_BP_CNT,
        }
        
        for reg_name, offset in global_regs.items():
            counters[reg_name] = await self._read_perf_register(offset)
            
        for n in range(self.n_streams):
            counters[f"PERF_INGR_HS_CNT_{n}"] = await self._get_perf_stream_counter(n, self.OFF_STREAM_INGR_HS_CNT)
            counters[f"PERF_INGR_BP_CNT_{n}"] = await self._get_perf_stream_counter(n, self.OFF_STREAM_INGR_BP_CNT)
            
        for w in range(self.w_workers):
            counters[f"PERF_EGR_WKR_BP_HS_CNT_{w}"] = await self._get_perf_worker_counter(w, self.OFF_WORKER_EGR_WKR_BP_HS_CNT)
            counters[f"PERF_EGR_WKR_BP_BP_CNT_{w}"] = await self._get_perf_worker_counter(w, self.OFF_WORKER_EGR_WKR_BP_BP_CNT)
            counters[f"PERF_EGR_WKR_BUS_HS_CNT_{w}"] = await self._get_perf_worker_counter(w, self.OFF_WORKER_EGR_WKR_BUS_HS_CNT)
            counters[f"PERF_EGR_WKR_BUS_BP_CNT_{w}"] = await self._get_perf_worker_counter(w, self.OFF_WORKER_EGR_WKR_BUS_BP_CNT)

        return counters

    async def _read_perf_register(self, offset):
        addr = self.PERF_MON_BASE + offset
        return await self.driver.read(addr)
    
    async def _get_single_perf_counter(self, offset):
        return await self._read_perf_register(offset)
    
    async def _get_perf_stream_counter(self, stream_id, stream_offset):
        offset = self.PERF_STREAM_BASE + stream_id * self.PERF_STREAM_STRIDE + stream_offset
        return await self._read_perf_register(offset)
    
    async def _get_perf_worker_counter(self, worker_id, worker_offset):
        offset = self.PERF_WORKER_BASE + worker_id * self.PERF_WORKER_STRIDE + worker_offset
        return await self._read_perf_register(offset)
    