import cocotb
import random as rnd

from cocotb.triggers import Timer

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()


@cocotb.test()
async def test_crossbar_routing(dut):
    rnd.seed(42)
    
    N_STREAMS = int(params["N_STREAMS"])
    M_MACROS = int(params["M_MACROS"])
    DATA_WIDTH = int(params["DATA_WIDTH"])
    ADDR_WIDTH = int(params["ADDR_WIDTH"])

    NUM_TESTS = 1000

    for test_idx in range(NUM_TESTS):
        targets = rnd.sample(range(M_MACROS), N_STREAMS)

        stream_data = [rnd.randint(0, (1 << DATA_WIDTH) - 1) for _ in range(N_STREAMS)]
        am_addr      = [rnd.randint(0, (1 << ADDR_WIDTH) - 1) for _ in range(N_STREAMS)]

        am_req = rnd.randint(0, (1 << N_STREAMS) - 1)
        bp_gnt = rnd.randint(0, (1 << M_MACROS) - 1)

        dut.am_req_i.value = am_req
        dut.bp_gnt_i.value = bp_gnt

        for n in range(N_STREAMS):
            dut.stream_data_i[n].value  = stream_data[n]
            dut.am_macro_sel_i[n].value = targets[n]
            dut.am_addr_i[n].value      = am_addr[n]

        await Timer(1, units='ns')

        stream_ready = int(dut.stream_ready_o.value)
        bp_req       = int(dut.bp_req_o.value)

        for m in range(M_MACROS):
            bp_req_m = (bp_req >> m) & 1
            bp_addr_n = int(dut.bp_addr_o[m].value)
            bp_wdata_n = int(dut.bp_wdata_o[m].value)

            if m in targets:
                n = targets.index(m)
                expected_req = (am_req >> n) & 1
                
                assert bp_req_m == expected_req, f"Test {test_idx}: bp_req_o mismatch on macro {m}: Expected: {expected_req} Got: {bp_req_m}"
                if expected_req == 1:
                    assert bp_addr_n == am_addr[n], f"Test {test_idx}: bp_addr_o mismatch on macro {m}: Expected: {am_addr[n]} Got: {bp_addr_n}"
                    assert bp_wdata_n == stream_data[n], f"Test {test_idx}: bp_wdata_o mismatch on macro {m}: Expected: {stream_data[n]} Got: {bp_wdata_n}"
                else:
                    assert bp_addr_n == 0, f"Test {test_idx}: bp_addr_o should be 0 on macro {m} when am_req_i is 0: Got: {bp_addr_n}"
                    assert bp_wdata_n == 0, f"Test {test_idx}: bp_wdata_o should be 0 on macro {m} when am_req_i is 0: Got: {bp_wdata_n}"

                expected_ready = (bp_gnt >> m) & 1 if expected_req == 1 else 0
                assert (stream_ready >> n) & 1 == expected_ready, f"Test {test_idx}: stream_ready_o mismatch on macro {m}: Expected: {expected_ready} Got: {(stream_ready >> n) & 1}"
            else:
                assert bp_req_m == 0, f"Test {test_idx}: bp_req_o should be 0 on unused macro {m}: Got: {bp_req_m}"
                assert bp_addr_n == 0, f"Test {test_idx}: bp_addr_o should be 0 on unused macro {m}: Got: {bp_addr_n}"
                assert bp_wdata_n == 0, f"Test {test_idx}: bp_wdata_o should be 0 on unused macro {m}: Got: {bp_wdata_n}"

            assert int(dut.bp_be_o[m].value) == 0xF, f"Test {test_idx}: bp_be_o should be 0xF on macro {m}."
