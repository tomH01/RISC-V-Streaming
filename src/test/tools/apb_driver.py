import cocotb

from cocotb.triggers import RisingEdge, ReadOnly


class APBDriver:
    def __init__(self, dut):
        self.dut = dut
        
        self._clear_bus()
        
    async def apb_write(self, addr, data):
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
        
    async def apb_read(self, addr):
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
        