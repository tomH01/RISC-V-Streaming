import cocotb
import abc
from cocotb.triggers import RisingEdge, ReadOnly


class CtrlDriver(abc.ABC):
    def __init__(self, dut):
        self.dut = dut
        self._clear_bus()
        
    @abc.abstractmethod
    async def write(self, addr, data):
        pass
    
    @abc.abstractmethod
    async def read(self, addr) -> int:
        pass
    
    @abc.abstractmethod
    def _clear_bus(self):
        pass



class APBDriver(CtrlDriver):
    def __init__(self, dut):
        super().__init__(dut)
        
        self._clear_bus()
        
    async def write(self, addr, data):
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 1
        self.dut.paddr_i.value = addr
        self.dut.psel_i.value = 1
        self.dut.pwdata_i.value = data
        
        await RisingEdge(self.dut.clk_i)
            
        self.dut.penable_i.value = 1
        
        while True:
            await ReadOnly()
            if int(self.dut.pready_o.value) == 1:
                break
        
            await RisingEdge(self.dut.clk_i)

        await RisingEdge(self.dut.clk_i)
        self._clear_bus()
        
    async def read(self, addr):
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 0
        self.dut.paddr_i.value = addr
        self.dut.psel_i.value = 1
        self.dut.pwdata_i.value = 0
        
        await RisingEdge(self.dut.clk_i)
            
        self.dut.penable_i.value = 1
        
        while True:
            await ReadOnly()
            if int(self.dut.pready_o.value) == 1:
                rdata = int(self.dut.prdata_o.value)
                break
        
            await RisingEdge(self.dut.clk_i)
        
        await RisingEdge(self.dut.clk_i)
        self._clear_bus()
        
        return rdata

    def _clear_bus(self):
        self.dut.penable_i.value = 0
        self.dut.pwrite_i.value = 0
        self.dut.paddr_i.value = 0
        self.dut.psel_i.value = 0
        self.dut.pwdata_i.value = 0
        
        
class AXILiteDriver(CtrlDriver):
    def __init__(self, dut):
        super().__init__(dut)
        
        self._clear_bus()
        
    async def write(self, addr, data, strb=0xF):
        self.dut.s_axi_ctrl_awaddr_i.value = addr
        self.dut.s_axi_ctrl_awvalid_i.value = 1
        
        self.dut.s_axi_ctrl_wdata_i.value = data
        self.dut.s_axi_ctrl_wstrb_i.value = strb
        self.dut.s_axi_ctrl_wvalid_i.value = 1
        
        aw_done = False
        w_done = False
        
        while not (aw_done and w_done):
            await RisingEdge(self.dut.clk_i)
            
            if not aw_done and self.dut.s_axi_ctrl_awready_o.value == 1:
                self.dut.s_axi_ctrl_awvalid_i.value = 0
                aw_done = True
            
            if not w_done and self.dut.s_axi_ctrl_wready_o.value == 1:
                self.dut.s_axi_ctrl_wvalid_i.value = 0
                w_done = True
                
        while self.dut.s_axi_ctrl_bvalid_o.value == 0:
            await RisingEdge(self.dut.clk_i)
            
    async def read(self, addr):
        self.dut.s_axi_ctrl_araddr_i.value = addr
        self.dut.s_axi_ctrl_arvalid_i.value = 1
        
        while True:
            await RisingEdge(self.dut.clk_i)
            if self.dut.s_axi_ctrl_arready_o.value == 1:
                self.dut.s_axi_ctrl_arvalid_i.value = 0
                break
            
        while self.dut.s_axi_ctrl_rvalid_o.value == 0:
            await RisingEdge(self.dut.clk_i)
            
        return int(self.dut.s_axi_ctrl_rdata_o.value)

    def _clear_bus(self):
        self.dut.s_axi_ctrl_awaddr_i.value = 0
        self.dut.s_axi_ctrl_awprot_i.value = 0
        self.dut.s_axi_ctrl_awvalid_i.value = 0
        
        self.dut.s_axi_ctrl_wdata_i.value = 0
        self.dut.s_axi_ctrl_wstrb_i.value = 0xF
        self.dut.s_axi_ctrl_wvalid_i.value = 0
        
        self.dut.s_axi_ctrl_bready_i.value = 1
        
        self.dut.s_axi_ctrl_araddr_i.value = 0
        self.dut.s_axi_ctrl_arprot_i.value = 0
        self.dut.s_axi_ctrl_arvalid_i.value = 0
        
        self.dut.s_axi_ctrl_rready_i.value = 1
        