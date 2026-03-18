import cocotb
from cocotb.triggers import ClockCycles
from cocotb.clock import Clock


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk_i, 5, units="ns").start())
    await ClockCycles(dut.clk_i, 1)
    dut.rst_ni.value = 0
    dut.req.value = 0
    dut.add.value = 0
    dut.wen.value = 1
    dut.wdata.value = 0
    dut.be.value = 0
    dut.gnt.value = 0
    
    await ClockCycles(dut.clk_i, 1)
    
    dut.rst_ni.value = 1
    
    await ClockCycles(dut.clk_i, 1)

async def write_memory(dut, addr, value):
    dut.wdata.value = value
    dut.wen.value = 0
    dut.req = 1
    dut.add = addr
    dut.be = 0xf
    await ClockCycles(dut.clk_i, 1)
    dut.wdata.value = 0
    dut.wen.value = 1
    dut.req = 0
    dut.add = 0
    dut.be = 0
    await ClockCycles(dut.clk_i, 1)


async def read_memory(dut, addr):
    dut.add = addr
    dut.req = 1
    dut.be = 0xf
    await ClockCycles(dut.clk_i, 1)
    dut.add = 0
    dut.req = 0
    dut.be = 0
    await ClockCycles(dut.clk_i, 1)
    

    
@cocotb.test()
async def test_top(dut):
    await reset_dut(dut)
    await write_memory(dut, 0x1C00_0000, 0xc0ffee)
    await ClockCycles(dut.clk_i, 10)
    await read_memory(dut, 0x1C00_0000)
    await ClockCycles(dut.clk_i, 10)
    
