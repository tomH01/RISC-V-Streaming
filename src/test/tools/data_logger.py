import os
import csv
from itertools import zip_longest

from utils.python.cocotb import get_design_parameters

params = get_design_parameters()    



class PerformanceLogger:
    def __init__(self, log_dir, filename_prefix):
        self.log_dir = log_dir
        self.filename_prefix = filename_prefix
        
        self.n_streams = int(params["N_STREAMS"])
        self.m_macros = int(params["M_MACROS"])
        self.macro_depth = int(params["MACRO_DEPTH"])
        self.b_banks = int(params["B_BANKS"])
        self.bank_depth = int(params["BANK_DEPTH"])
        self.w_workers = int(params["W_WORKERS"])
    
    
    def dump_perf_counters(self, counters):
        if counters is None:
            raise ValueError("Counters dictionary is None")
        
        base_name = self._gen_csv_filename()
        filename = base_name.replace("perf", "perf_counters")
        file_path = os.path.join(self.log_dir, filename)
        
        row_data = {
            "N_STREAMS": self.n_streams,
            "M_MACROS": self.m_macros,
            "MACRO_DEPTH": self.macro_depth,
            "B_BANKS": self.b_banks,
            "BANK_DEPTH": self.bank_depth,
            "W_WORKERS": self.w_workers,
            **counters
        }
        
        with open(file_path, 'w', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=list(row_data.keys()))
            writer.writeheader()
            writer.writerow(row_data)
            
    def dump_latencies(self, block_tracker):
        if not block_tracker:
            return

        stream_latencies = {}
        for stream_id, phases in block_tracker.items():
            ingress_list = phases.get("ingress", [])
            egress_list = phases.get("egress", [])
            
            latencies = [eg - ig for ig, eg in zip(ingress_list, egress_list)]
            stream_latencies[f"stream_{stream_id}_latency"] = latencies

        base_name = self._gen_csv_filename()
        filename = base_name.replace("perf", "perf_latencies")
        file_path = os.path.join(self.log_dir, filename)

        fieldnames = list(stream_latencies.keys())
        
        columns = list(stream_latencies.values())
        rows = zip_longest(*columns, fillvalue="")

        with open(file_path, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(fieldnames)
            writer.writerows(rows)
        
    def _gen_csv_filename(self):
        return (
            f"{self.filename_prefix}_n{self.n_streams}_m{self.m_macros}"
            f"_md{self.macro_depth}_b{self.b_banks}_bd{self.bank_depth}_w{self.w_workers}.csv"
        )
        