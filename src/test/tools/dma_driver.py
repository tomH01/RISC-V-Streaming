import cocotb
from cocotb.triggers import RisingEdge

from base_driver import BaseDriver

from utils.python.cocotb import get_design_parameters
params = get_design_parameters()


class DMADriver(BaseDriver):
    META_BASE = 0x0010_0000
    CPU_DONE_PTR = 0x80
    FIFO_TOP = 0x84
    
    def __init__(self, dut, ctrl_driver, data_driver):
        self.dut = dut
        self.ctrl_driver = ctrl_driver
        self.data_driver = data_driver
        
        self.m_macros = int(params["M_MACROS"])
        self.data_width = int(params["DATA_WIDTH"])
        self.data_width_b = self.data_width // 8
        
        
    async def setup_ingress_cfg(self, configs, topology):
        await self._send_topology_cfg(topology)
        
        for stream_id, cfg in configs.items():
            await self._send_stream_cfg(stream_id, cfg)
            
    async def setup_global_cfg(self, bank_base):
        await self.ctrl_driver.send_global_config("bank_base", bank_base)
        await RisingEdge(self.dut.clk_i)
        await self.ctrl_driver.send_global_config("dma_enable", self.ctrl_driver.get_enable(True))   
            
    async def activate_streams(self, configs):
        for stream_id in configs.keys():
            await self._activate_stream(stream_id)     
            
    async def send_egress_cfg(self, stream_id, idx, cfg):
        pass
    
    async def read_agu_done_ptr(self, stream_id):
        addr = self.META_BASE + (stream_id * self.data_width_b)
        return await self.data_driver.read(addr)
    
    async def write_cpu_done_ptr(self, value):
        addr = self.META_BASE + self.CPU_DONE_PTR
        await self.data_driver.write(addr, value)
        
    async def read_fifo_top(self):
        addr = self.META_BASE + self.FIFO_TOP
        return await self.data_driver.read(addr)
    
    def decode_dispatch_data(self, data):
        stream_id = (data >> 27) & 0x1F
        size = data & 0x7FF_FFFF
        return stream_id, size

    async def _send_stream_cfg(self, stream_id, cfg):
        await self.ctrl_driver.send_ingress_config("start_macro", cfg["start_macro"], stream_id)
        await self.ctrl_driver.send_ingress_config("window_size", 100, stream_id) #cfg["window_size"], stream_id)
        await self.ctrl_driver.send_stream_interval(stream_id, 1) #cfg["interval"])
        
    async def _send_topology_cfg(self, topology):
        for i in range(0, self.m_macros, 2):
            await self.ctrl_driver.send_topology_pair(i, topology)
        
    async def _activate_stream(self, stream_id):
        await self.ctrl_driver.send_ingress_config("stream_en", 1, stream_id)  
    