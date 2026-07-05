import cocotb
import random as rnd

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly, NextTimeStep
from cocotb_coverage.coverage import CoverPoint, CoverCross, coverage_db

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()

@CoverPoint(
    "buffer_pool.egress.macro_select",
    xf=lambda macro_id: macro_id,
    bins=list(range(int(params["M_MACROS"])))
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
    def __init__(self, dut, m_macros, num_read_ports):
        self.dut = dut
        self.m_macros = m_macros
        self.num_read_ports = num_read_ports
        
        self.dut.ingr_done_i.value = 0   
        self.dut.egr_release_i.value = 0
        self.dut.ingr_req_i.value = 0

        for i in range(self.m_macros):
            self.dut.ingr_addr_i[i].value = 0
            self.dut.ingr_wdata_i[i].value = 0
            self.dut.ingr_be_i[i].value = 0

        self.dut.egr_req_i.value = 0

        for i in range(num_read_ports):
            self.dut.egr_addr_i[i].value = 0
            self.dut.egr_macro_select_i[i].value = 0

    async def reset(self):
        self.dut.rst_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)


    async def set_owner_ingr(self, macro_idx):
        self.dut.egr_release_i[macro_idx].value = 1

    async def set_owner_egr(self, macro_idx):
        self.dut.ingr_done_i[macro_idx].value = 1
        
    async def write_ingress(self, macro_idx, addr, data, be=0xF):
        cover_address(addr)
        cover_byte_enable(be)

        self.dut.ingr_req_i[macro_idx].value = 1     
        self.dut.ingr_addr_i[macro_idx].value = addr
        self.dut.ingr_wdata_i[macro_idx].value = data
        self.dut.ingr_be_i[macro_idx].value = be

    async def read_egress(self, port_idx, macro_idx, addr):
        cover_egress_select(macro_idx)
        cover_address(addr)

        self.dut.egr_req_i[port_idx].value = 1
        self.dut.egr_addr_i[port_idx].value = addr
        self.dut.egr_macro_select_i[port_idx].value = macro_idx
        
@cocotb.test()
async def test_rw_coverage(dut):
    rnd.seed(42)
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    m_macros = int(params["M_MACROS"])
    num_read_ports = int(params["NUM_READ_PORTS"])
    macro_depth = int(params["MACRO_DEPTH"])

    driver = BufferPoolDriver(dut, m_macros, num_read_ports)
    await driver.reset()
    
    scoreboard = {i: {} for i in range(m_macros)}
    macro_owners = [0] * m_macros  
    
    NUM_CYCLES = 10000
    num_writes = 0
    num_reads = 0    
    
    active_read_pipeline = []
    pending_owner_change = {}
    
    for _ in range(NUM_CYCLES):
        await ReadOnly()
        
        finished_reads = [r for r in active_read_pipeline if r[0] == 0]
        active_read_pipeline = [(c - 1, p, d, a, m) for c, p, d, a, m in active_read_pipeline if c > 0]
        
        for cycles, port_idx, expected_data, addr, m_idx in finished_reads:
            data = dut.egr_r_rdata_o[port_idx].value
            valid = dut.egr_r_valid_o[port_idx].value
            
            assert valid == 1, f"Egress read data not valid for port {port_idx}."
            assert data == expected_data, f"Read {num_reads} at {hex(addr)}: Data mismatch at Macro {m_idx}: {hex(data)}, Expected: {hex(expected_data)}."
        
        await RisingEdge(dut.clk_i)
        
        for m_idx in range(m_macros):
            dut.ingr_req_i[m_idx].value = 0
            dut.ingr_addr_i[m_idx].value = 0
            dut.ingr_wdata_i[m_idx].value = 0
            dut.ingr_be_i[m_idx].value = 0
            dut.ingr_done_i[m_idx].value = 0
            dut.egr_release_i[m_idx].value = 0
            
        for p in range(num_read_ports):
            dut.egr_req_i[p].value = 0
            
        for m_idx, new_state in pending_owner_change.items():
            macro_owners[m_idx] = new_state
        pending_owner_change.clear()   
        
        for m_idx in range(m_macros):
            if macro_owners[m_idx] == 0:
                if rnd.random() < 0.5:
                    addr = rnd.randrange(macro_depth)
                    data = rnd.randint(0, 0xFFFFFFFF)

                    await driver.write_ingress(m_idx, addr * 4, data)
                    scoreboard[m_idx][addr] = data
                    num_writes += 1

                    if rnd.random() < 0.3 or len(scoreboard[m_idx]) > 10:
                        await driver.set_owner_egr(m_idx)
                        pending_owner_change[m_idx] = 1
                        
        available_egr = [i for i , owner in enumerate(macro_owners) if owner == 1 and len(scoreboard[i]) > 0]
                        
        ports = list(range(num_read_ports))
        rnd.shuffle(ports)        
        for port_idx in ports:
            if not available_egr:
                    break
            
            if rnd.random() < 0.8:
                m_idx = rnd.choice(available_egr)
                available_egr.remove(m_idx)
                
                addr = rnd.choice(list(scoreboard[m_idx].keys()))
                expected_data = scoreboard[m_idx][addr]
                
                await driver.read_egress(port_idx, m_idx, addr * 4)
                
                active_read_pipeline.append((1, port_idx, expected_data, addr, m_idx))
                num_reads += 1
                
                if rnd.random() < 0.2:
                    await driver.set_owner_ingr(m_idx)
                    pending_owner_change[m_idx] = 0

    coverage_db.report_coverage(dut.log.info, bins=True)
