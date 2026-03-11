import cocotb
import random as rnd

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb_coverage.coverage import CoverPoint, CoverCross, coverage_db

@CoverPoint(
    "buffer_pool.egress.macro_select",
    xf=lambda macro_id: macro_id,
    bins=list(range(16))
)
def cover_egress_select(macro_id):
    pass

@CoverPoint(
    "buffer_pool.address.ranges",
    xf=lambda addr: addr,
    bins=[0, 1020],
    bins_labels=["min", "max"]
)
def cover_address(addr):
    pass

@CoverPoint(
    "buffer_pool.ingress.byte_enables",
    xf=lambda be: be,
    bins=[1, 2, 3, 4, 8, 12, 15]
)
def cover_byte_enable(be):
    pass

class BufferPoolDriver:
    def __init__(self, dut, m_macros, nb_read_ports):
        self.dut = dut
        self.m_macros = m_macros
        self.nb_read_ports = nb_read_ports
        
        self.dut.macro_owner.value = 0
        self.dut.in_req.value = 0

        for i in range(self.m_macros):
            self.dut.in_add[i].value = 0
            self.dut.in_wdata[i].value = 0
            self.dut.in_be[i].value = 0

        self.dut.out_req.value = 0

        for i in range(nb_read_ports):
            self.dut.out_add[i].value = 0
            self.dut.out_macro_select[i].value = 0

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)

    def set_owner(self, macro_idx, owner):
        self.dut.macro_owner[macro_idx].value = owner

    async def write_ingress(self, macro_idx, addr, data, be=0xF):
        cover_address(addr)
        cover_byte_enable(be)

        self.dut.in_add[macro_idx].value = addr
        self.dut.in_wdata[macro_idx].value = data
        self.dut.in_be[macro_idx].value = be
        self.dut.in_req[macro_idx].value = 1

        await RisingEdge(self.dut.clk_i)
        await ReadOnly()

        gnt = self.dut.in_gnt[macro_idx].value
        assert gnt == 1, f"Ingress grant failed for macro {macro_idx}."

        await RisingEdge(self.dut.clk_i)
        self.dut.in_req[macro_idx].value = 0


    async def read_egress(self, port_idx, macro_idx, addr):
        cover_egress_select(macro_idx)
        cover_address(addr)

        self.dut.out_macro_select[port_idx].value = macro_idx
        self.dut.out_add[port_idx].value = addr
        self.dut.out_req[port_idx].value = 1

        await RisingEdge(self.dut.clk_i)
        await ReadOnly()

        gnt = self.dut.out_gnt[port_idx].value
        assert gnt == 1, f"Ingress grant failed for port {port_idx}."

        await RisingEdge(self.dut.clk_i)
        self.dut.out_req[port_idx].value = 0

        await ReadOnly()

        valid = self.dut.out_r_valid[port_idx].value
        assert valid == 1, f"Egress r_valid for port {port_idx} missing."

        data = self.dut.out_r_rdata[port_idx].value
        return data
    

@cocotb.test()
async def test_rw_coverage(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    m_macros = int(dut.M_MACROS.value)
    nb_read_ports = int(dut.NB_READ_PORTS.value)

    env = BufferPoolDriver(dut, m_macros, nb_read_ports)
    await env.reset()

    for macro_id in range(m_macros):
        env.set_owner(macro_id, 0)
        test_addr = rnd.choice([0, 1020, rnd.randrange(4, 1020, 4)])
        test_data = rnd.randint(0, 0xFFFFFFFF)

        await env.write_ingress(macro_id, test_addr, test_data)

        env.set_owner(macro_id, 1)

        read_port = rnd.randint(0, nb_read_ports - 1)
        read_data = await env.read_egress(read_port, macro_id, test_addr)

        assert read_data == test_data, f"Data mismatch in macro {macro_id} at {hex(test_addr)}: Read: {read_data}, Expected: {test_data}."

        await RisingEdge(dut.clk_i)

    coverage_db.report_coverage(dut.log.info, bins=True)
