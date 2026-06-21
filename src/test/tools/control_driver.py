import cocotb

from cocotb.triggers import RisingEdge

from apb_driver import APBDriver


class ControlDriver:
    
    GLOBAL_BASE = 0x0000
    STREAM_BASE = 0x1000
    TOPOLOGY_BASE = 0x2000
    INTERVAL_BASE = 0x3000
    
    STREAM_STRIDE = 0x20
    
    OFF_START_MACRO = 0x00
    OFF_WINDOW_SIZE = 0x04
    OFF_STREAM_EN = 0x08
    
    OFF_EGRESS_SHADOW_0 = 0x10
    OFF_EGRESS_SHADOW_1 = 0x14
    OFF_EGRESS_SHADOW_2 = 0x18
    OFF_EGRESS_TRIGGER = 0x1C
    
    def __init__(self, dut, n_streams, m_macros):
        self.dut = dut
        self.n_streams = n_streams
        self.m_macros = m_macros
        
        self.apb = APBDriver(dut)  
        
    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        
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
        lower_macro = total_topology.get(macro_idx, None)
        upper_macro = total_topology.get(macro_idx + 1, None)
        
        if lower_macro is None or upper_macro is None:
            return
        
        addr = self.TOPOLOGY_BASE + (macro_idx // 2) * 0x4
        packed_data =  (upper_macro << 16) | lower_macro
        
        await self.apb.apb_write(addr, packed_data)

        
    