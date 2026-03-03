import os
import subprocess
import sys
import shutil
import re
import functools

import click
from loguru import logger
from pathlib import Path


def __subprocess_run(cwd, env, command, error_message=None, capture_output=False):
    try:
        sp = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            env=env,
            check=True,
            capture_output=capture_output,
            encoding="utf-8",
        )
    except subprocess.CalledProcessError:
        if error_message is None:
            error_message = f"Command failed: {command}"
        logger.error(error_message)
        sys.exit(1)
    if capture_output:
        return sp

@click.option("--synthesis")
@click.option("--simulation")
@click.pass_obj
def run(ctx, synthesis, simulation):
    bottle_home = Path(ctx.bottle.home).resolve()
    bottle_name = ctx.bottle.name
    env = os.environ.copy()
    subprocess_run = functools.partial(__subprocess_run, bottle_home, env)

    eval_out = bottle_home / "output/eval"

    eval_out.mkdir(exist_ok=True, parents=True)

    nums_entries_pc_driven_map = [8, 16, 32, 64, 128]
    # nums_entries_pc_driven_map = [64]

    # run_synthesis = False
    # run_simulation = True

    fix_parameters = "-p NUM_MEM_BANKS 8 -p DELAY_STAGES 2"

    if synthesis:
        for num_entries in nums_entries_pc_driven_map:
            command = f'teda {bottle_name} synthesis -p NUM_ENTRIES_PC_DRIVEN_MAP {num_entries} {fix_parameters} -msg "e{num_entries}"'
            subprocess_run(command)

    if simulation:
        for num_entries in nums_entries_pc_driven_map:
            commands = [
                f'teda {bottle_name} resym synthesis "mock_streaming_e{num_entries}"',
                f'teda {bottle_name} simulation -c postsyn -p COCOTB_TESTCASE pmc_test_pc_driven -p NUM_ENTRIES_PC_DRIVEN_MAP {num_entries} {fix_parameters} -msg "e{num_entries}"',
                f'teda {bottle_name} resym simulation "postsyn_e{num_entries}"',
                f'teda {bottle_name} power -msg "e{num_entries}"',
            ]
            for c in commands:
                subprocess_run(c)
    
    for num_entries in nums_entries_pc_driven_map:
        power_report = bottle_home / f"output/power/postsyn_e{num_entries}/reports/typ/postsyn.power.rpt"
        if not power_report.exists():
            break
        with power_report.open() as f:
            report = f.readlines()
        
        header_index = [i for i,x in enumerate(report) if x.startswith("Cells")][0]
        header = report[header_index].strip().split()
        pmc_apb = report[header_index + 2].strip().split()
        # pmc_internal_module = report[27].strip().split()
        total_power = float(pmc_apb[header.index('Total')])
        print(f"({num_entries}, {round(total_power*1000,4)})")
