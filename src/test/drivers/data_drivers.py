import asyncio
import cocotb

from cocotb.triggers import RisingEdge, ReadOnly

from cpu_state import CPUOp 
from utils.python.cocotb import get_design_parameters
params = get_design_parameters()


class AXIDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.clear_bus()
        
    def clear_bus(self):
        self.dut.s_axi_data_awid_i.value = 0
        self.dut.s_axi_data_awaddr_i.value = 0
        self.dut.s_axi_data_awlen_i.value = 0
        self.dut.s_axi_data_awsize_i.value = 2
        self.dut.s_axi_data_awburst_i.value = 1
        self.dut.s_axi_data_awlock_i.value = 0
        self.dut.s_axi_data_awcache_i.value = 0
        self.dut.s_axi_data_awprot_i.value = 0
        self.dut.s_axi_data_awqos_i.value = 0
        self.dut.s_axi_data_awregion_i.value = 0
        self.dut.s_axi_data_awuser_i.value = 0
        self.dut.s_axi_data_awvalid_i.value = 0
        
        self.dut.s_axi_data_wdata_i.value = 0
        self.dut.s_axi_data_wstrb_i.value = 0xF
        self.dut.s_axi_data_wlast_i.value = 0
        self.dut.s_axi_data_wuser_i.value = 0
        self.dut.s_axi_data_wvalid_i.value = 0
        
        self.dut.s_axi_data_bready_i.value = 1
        
        self.dut.s_axi_data_arid_i.value = 0
        self.dut.s_axi_data_araddr_i.value = 0
        self.dut.s_axi_data_arlen_i.value = 0
        self.dut.s_axi_data_arsize_i.value = 2
        self.dut.s_axi_data_arburst_i.value = 1
        self.dut.s_axi_data_arlock_i.value = 0
        self.dut.s_axi_data_arcache_i.value = 0
        self.dut.s_axi_data_arprot_i.value = 0
        self.dut.s_axi_data_arqos_i.value = 0
        self.dut.s_axi_data_arregion_i.value = 0
        self.dut.s_axi_data_aruser_i.value = 0
        self.dut.s_axi_data_arvalid_i.value = 0
        
        self.dut.s_axi_data_rready_i.value = 1
        
    async def write(self, addr, data, strb=0xF, id=0):
        self.dut.s_axi_data_awid_i.value = id
        self.dut.s_axi_data_awaddr_i.value = addr
        self.dut.s_axi_data_awlen_i.value = 0
        self.dut.s_axi_data_awsize_i.value = 2
        self.dut.s_axi_data_awvalid_i.value = 1
        
        self.dut.s_axi_data_wdata_i.value = data
        self.dut.s_axi_data_wstrb_i.value = strb
        self.dut.s_axi_data_wlast_i.value = 1
        self.dut.s_axi_data_wvalid_i.value = 1
        
        aw_done = False
        w_done = False
        
        while not (aw_done and w_done):
            await RisingEdge(self.dut.clk_i)
            
            if not aw_done and self.dut.s_axi_data_awready_o.value == 1:
                self.dut.s_axi_data_awvalid_i.value = 0
                aw_done = True
            
            if not w_done and self.dut.s_axi_data_wready_o.value == 1:
                self.dut.s_axi_data_wvalid_i.value = 0
                self.dut.s_axi_data_wlast_i.value = 0
                w_done = True
                
        while self.dut.s_axi_data_bvalid_o.value == 0:
            await RisingEdge(self.dut.clk_i)    
            
    async def read(self, addr, id=0):
        data_list = await self.read_burst(addr, length=1, id=id)
        return data_list[0]

    async def read_burst(self, addr, length=1, id=0):
        self.dut.s_axi_data_arid_i.value = id
        self.dut.s_axi_data_araddr_i.value = addr
        self.dut.s_axi_data_arlen_i.value = length - 1
        self.dut.s_axi_data_arsize_i.value = 2
        self.dut.s_axi_data_arvalid_i.value = 1
        
        while True:
            await RisingEdge(self.dut.clk_i)
            if self.dut.s_axi_data_arready_o.value == 1:
                self.dut.s_axi_data_arvalid_i.value = 0
                break
            
        read_data = []
        while True:
            await RisingEdge(self.dut.clk_i)
            if self.dut.s_axi_data_rvalid_o.value == 1:
                read_data.append(int(self.dut.s_axi_data_rdata_o.value))
                
                if self.dut.s_axi_data_rlast_o.value == 1:
                    break

        return read_data
    
    
class OBIDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self.clear_bus()
        
    def clear_bus(self):
        self.dut.data_req_i.value = 0
        self.dut.data_addr_i.value = 0
        self.dut.data_wdata_i.value = 0
        self.dut.data_be_i.value = 0
        self.dut.data_we_i.value = 0
        
    
    def write(self, addr, wdata, be=0xF):
        self.dut.data_req_i.value = 1
        self.dut.data_addr_i.value = addr
        self.dut.data_wdata_i.value = wdata 
        self.dut.data_be_i.value = be
        self.dut.data_we_i.value = 1
        
    async def read(self, addr):
        self.dut.data_req_i.value = 1
        self.dut.data_addr_i.value = addr
        self.dut.data_we_i.value = 0
        await RisingEdge(self.dut.clk_i)
        self.dut.data_req_i.value = 0
        
        await ReadOnly()
        while self.dut.data_gnt_o.value == 0:
            await RisingEdge(self.dut.clk_i)
            await ReadOnly()
        return int(self.dut.data_rdata_o.value)
        
    
    def read_init(self, addr):
        self.dut.data_req_i.value = 1
        self.dut.data_addr_i.value = addr
        self.dut.data_we_i.value = 0
        return (CPUOp.READ_DATA, addr)
    