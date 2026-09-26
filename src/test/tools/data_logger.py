import os
import csv

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
        
        file_path = os.path.join(self.log_dir, self._gen_csv_filename())
        
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
        
    def _gen_csv_filename(self):
        return (
            f"{self.filename_prefix}_n{self.n_streams}_m{self.m_macros}"
            f"_md{self.macro_depth}_b{self.b_banks}_bd{self.bank_depth}_w{self.w_workers}.csv"
        )
        