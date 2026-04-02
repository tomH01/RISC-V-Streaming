import random
import cocotb

from cocotb.triggers import Combine, ReadOnly, RisingEdge
from cocotb.clock import Clock
from cocotb_coverage.coverage import CoverPoint, coverage_db


async def upstream_driver(dut, expected_queue, num_items):
    dut.us_valid_i.value = 0

    for _ in range(num_items):
        while random.random() < 0.3:
            dut.us_valid_i.value = 0
            for _ in range(random.randint(1, 5)):
                await RisingEdge(dut.clk_i)

        data_val = random.randint(0, 0xFFFFFFFF)
        dut.us_data_i.value = data_val
        dut.us_valid_i.value = 1

        await ReadOnly()
        while dut.us_ready_o.value == 0:
            await RisingEdge(dut.clk_i)
            await ReadOnly()

        expected_queue.append(data_val)
        await RisingEdge(dut.clk_i)
    
    dut.us_valid_i.value = 0


async def downstream_receiver(dut, expected_queue, num_items):
    dut.ds_ready_i.value = 0
    items_received = 0

    while items_received < num_items:
        dut.ds_ready_i.value = 1 if random.random() < 0.7 else 0

        await ReadOnly()

        if dut.ds_valid_o.value == 1 and dut.ds_ready_i.value == 1:
            actual_data = int(dut.ds_data_o.value)

            assert len(expected_queue) > 0, "Received data when expected queue is empty"

            expected_data = expected_queue.pop(0)
            assert actual_data == expected_data, f"Data mismatch: expected {expected_data}, got {actual_data}"

            items_received += 1
        
        await RisingEdge(dut.clk_i)



@CoverPoint("top.input_interface",
            xf=lambda valid, ready: (valid, ready),
            bins=[(0, 0), (0, 1), (1, 0), (1, 1)])
def sample_input(valid, ready):
    pass

@CoverPoint("top.output_interface",
            xf=lambda valid, ready: (valid, ready),
            bins=[(0, 0), (0, 1), (1, 0), (1, 1)])
def sample_output(valid, ready):
    pass

async def coverage_collector(dut):
    while True:
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        sample_input(dut.us_valid_i.value, dut.us_ready_o.value)
        sample_output(dut.ds_valid_o.value, dut.ds_ready_i.value)


@cocotb.test()
async def test_in_stream_channel(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    dut.rst_ni.value = 0
    dut.us_data_i.value = 0
    dut.us_valid_i.value = 0

    for _ in range(3):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)

    expected_queue = []
    NUM_ITEMS = 1000

    cocotb.start_soon(coverage_collector(dut))

    driver_task = cocotb.start_soon(upstream_driver(dut, expected_queue, NUM_ITEMS))
    receiver_task = cocotb.start_soon(downstream_receiver(dut, expected_queue, NUM_ITEMS))

    await Combine(driver_task, receiver_task)

    assert len(expected_queue) == 0, f"Expected queue not empty at end of test: {expected_queue}"

    coverage_db.report_coverage(cocotb.log.info, bins=True)
