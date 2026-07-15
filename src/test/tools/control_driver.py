import cocotb

from cocotb.triggers import RisingEdge

from apb_driver import APBDriver

from utils.python.cocotb import get_design_parameters
params = get_design_parameters()


class ControlDriver:
    
    GLOBAL_BASE = 0x08000000
    STREAM_BASE = 0x08001000
    TOPOLOGY_BASE = 0x08002000
    INTERVAL_BASE = 0x08003000
    
    GLOBAL_CONTROL = 0x00
    BANK_LIMIT_B = 0x04
    BANK_BASE_OFFSET = 0x20    
    
    STREAM_STRIDE = 0x20
    
    OFF_START_MACRO = 0x00
    OFF_WINDOW_SIZE = 0x04
    OFF_STREAM_EN = 0x08
    
    OFF_EGRESS_SHADOW_0 = 0x10
    OFF_EGRESS_SHADOW_1 = 0x14
    OFF_EGRESS_SHADOW_2 = 0x18
    OFF_EGRESS_TRIGGER = 0x1C
    
    def __init__(self, dut):
        self.dut = dut
        self.n_streams = int(params["N_STREAMS"])
        self.m_macros = int(params["M_MACROS"])
        self.b_banks = int(params["B_BANKS"])
        
        self.apb = APBDriver(dut)  
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
    async def send_global_config(self, config_type, data, bank_idx=None):
        if config_type == "bank_base" and bank_idx is None:
            raise ValueError("bank_idx must be provided for bank_base config")
        
        match config_type:
            case "global_ctrl":
                addr = self.GLOBAL_BASE + self.GLOBAL_CONTROL
            case "bank_limit_b":
                addr = self.GLOBAL_BASE + self.BANK_LIMIT_B
            case "bank_base":
                addr = self.GLOBAL_BASE + self.BANK_BASE_OFFSET + bank_idx * 0x4
            case _:
                raise ValueError(f"Unknown config type: {config_type}")
                
        await self.apb.apb_write(addr, data)
        
    async def send_ingress_config(self, config_type, data, stream_id):    
        stream_addr = self.STREAM_BASE + stream_id * self.STREAM_STRIDE
        
        match config_type:
            case "start_macro":
                addr = stream_addr + self.OFF_START_MACRO
            case "window_size":
                addr = stream_addr + self.OFF_WINDOW_SIZE
            case "stream_en":
                addr = stream_addr + self.OFF_STREAM_EN
            case _:
                raise ValueError(f"Unknown config type: {config_type}")
                
        await self.apb.apb_write(addr, data)

    async def send_egress_config(self, stream_id, idx, data):
        offset = self.OFF_EGRESS_SHADOW_0 + 0x4 * idx
        addr = self.STREAM_BASE + stream_id * self.STREAM_STRIDE + offset
        
        await self.apb.apb_write(addr, data)
        
    async def send_stream_interval(self, stream_id, interval):
        addr = self.INTERVAL_BASE + stream_id * 0x4
        await self.apb.apb_write(addr, interval)
        
    async def send_topology_pair(self, macro_idx, total_topology):
        lower_macro = total_topology.get(macro_idx, macro_idx)
        upper_macro = total_topology.get(macro_idx + 1, macro_idx + 1)
        
        if lower_macro is None or upper_macro is None:
            return
        
        addr = self.TOPOLOGY_BASE + (macro_idx // 2) * 0x4
        packed_data =  (upper_macro << 16) | lower_macro
        
        await self.apb.apb_write(addr, packed_data)
        
    def get_global_control(self, dma_enable):
        dma_bit = (int(dma_enable) & 0x1) << 31
        return dma_bit        
    