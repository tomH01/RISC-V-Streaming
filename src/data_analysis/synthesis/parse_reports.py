import argparse
from pathlib import Path
import re
from typing import Optional, Union
import pandas as pd


class SynthesisReportCollector:
    def __init__(self, project_root: Optional[Path] = None):
        self.project_root = (
            project_root or Path(__file__).resolve().parents[3]
        )
        self.output_dir = self.project_root / "output" / "synthesis"

    def _parse_area_report(self, rpt_file: Path) -> dict[str, dict[str, str]]:
        if not rpt_file.exists():
            return {}

        content = rpt_file.read_text().splitlines()
        cols = []
        table_rows = []
        in_header = False
        in_data = False

        for line in content:
            if "Total-Area" in line:
                cols = [c.strip() for c in re.split(r"\s{2,}", line) if c.strip()]
                in_header = True
                continue

            if in_header and not in_data:
                in_data = True
                continue

            if in_data and line.strip().startswith("---"):
                break

            if in_data and line.strip():
                indent = len(line) - len(line.lstrip())
                tokens = line.split()
                if tokens:
                    table_rows.append((indent, tokens))

        if not cols or not table_rows:
            return {}

        parsed_nodes = {}
        path_stack = []
        prev_indent = -1

        for indent, tokens in table_rows:
            inst_name = tokens[0]

            if indent > prev_indent:
                path_stack.append(inst_name)
            elif indent < prev_indent:
                pop_count = (prev_indent - indent) // 2 + 1
                path_stack = path_stack[:-pop_count] + [inst_name]
            else:
                path_stack = path_stack[:-1] + [inst_name]

            prev_indent = indent
            full_path = "/" + "/".join(path_stack)

            data_values = tokens[1:]
            metric_cols = [c for c in cols if c != "Instance"]

            row_dict = {}
            for col_name, val in zip(reversed(metric_cols), reversed(data_values)):
                row_dict[col_name] = val

            parsed_nodes[full_path] = row_dict

        return parsed_nodes

    def _parse_power_report(self, rpt_file: Path) -> dict[str, dict[str, str]]:
        if not rpt_file.exists():
            return {}

        content = rpt_file.read_text().splitlines()
        in_data = False
        parsed_nodes = {}

        for line in content:
            if "Cells" in line and "Leakage" in line:
                in_data = True
                continue

            if in_data and line.strip().startswith("---"):
                if parsed_nodes:
                    break
                continue

            if in_data and line.strip():
                tokens = line.split()
                if len(tokens) >= 7:
                    inst_path = tokens[-1]
                    parsed_nodes[inst_path] = {
                        "Leakage": tokens[2],
                        "Internal": tokens[3],
                        "Switching": tokens[4],
                        "Total": tokens[5],
                    }

        return parsed_nodes

    def _parse_timing_report(self, rpt_file: Path) -> dict[str, float]:
        if not rpt_file.exists():
            return {}

        content = rpt_file.read_text()
        timing_data = {}

        patterns = {
            "Slack_ps": r"Slack:=\s*(-?\d+(?:\.\d+)?)",
            "DataPath_ps": r"Data Path:-\s*(\d+(?:\.\d+)?)",
            "ReqTime_ps": r"Required Time:=\s*(\d+(?:\.\d+)?)",
            "ClockPeriod_ps": r"Clock Edge:\+\s*(\d+(?:\.\d+)?)",
        }

        for key, pattern in patterns.items():
            match = re.search(pattern, content)
            if match:
                timing_data[key] = float(match.group(1))

        return timing_data

    def _load_runs_from_file(self, file_path: Path) -> list[Union[str, tuple[str, float]]]:
        if not file_path.exists():
            raise FileNotFoundError(f"Runs-Datei nicht gefunden: {file_path}")

        if file_path.suffix == ".csv":
            runs_df = pd.read_csv(file_path)
            if "run_name" in runs_df.columns:
                if "param" in runs_df.columns:
                    return list(zip(runs_df["run_name"], runs_df["param"]))
                return runs_df["run_name"].tolist()

        lines = [line.strip() for line in file_path.read_text().splitlines() if line.strip() and not line.startswith("#")]
        return lines

    def collect_data(
        self,
        synth_runs: Union[list[str | tuple[str, float | int]], str, Path],
        instances: list[tuple[str, str]],
        area_datas: list[str],
        power_datas: Optional[list[str]] = None,
        include_timing: bool = True,
        save_csv: Optional[Union[str, Path]] = None,
    ) -> pd.DataFrame:
        if isinstance(synth_runs, (str, Path)):
            runs_file = Path(synth_runs)
            synth_runs = self._load_runs_from_file(runs_file)

        rows = []

        for run_item in synth_runs:
            if isinstance(run_item, tuple):
                run_name, param_val = run_item
            else:
                run_name = run_item
                match = re.search(r"(\d+(?:\.\d+)?)", run_name)
                param_val = float(match.group(1)) if match else run_name

            run_dir = self.output_dir / run_name / "reports" / "final"
            area_file = run_dir / "area.rpt"
            power_file = run_dir / "power.typ.rpt"
            timing_file = run_dir / "timing.typ.rpt"

            if not area_file.exists():
                print(f"Warning: File not found: {area_file}")
                continue

            parsed_area = self._parse_area_report(area_file)
            parsed_power = self._parse_power_report(power_file)

            row = {"run_name": run_name, "param": param_val}

            for pattern, alias in instances:
                matched_area_path = next(
                    (p for p in parsed_area if p.endswith(pattern) or pattern in p), None
                )
                matched_power_path = next(
                    (p for p in parsed_power if p.endswith(pattern) or pattern in p), None
                )

                if matched_area_path:
                    node_data = parsed_area[matched_area_path]
                    for metric in area_datas:
                        if metric in node_data:
                            val = node_data[metric]
                            row[f"{alias}_{metric}"] = (
                                float(val) if "." in str(val) else int(val)
                            )

                if matched_power_path and power_datas:
                    node_data = parsed_power[matched_power_path]
                    for metric in power_datas:
                        if metric in node_data:
                            row[f"{alias}_{metric}"] = float(node_data[metric])

            if include_timing and timing_file.exists():
                timing_info = self._parse_timing_report(timing_file)
                for key, val in timing_info.items():
                    row[f"Timing_{key}"] = val

            rows.append(row)

        df = pd.DataFrame(rows)
        if not df.empty and "param" in df.columns:
            try:
                df = df.sort_values("param").reset_index(drop=True)
            except TypeError:
                pass
            
        if save_csv and not df.empty:
            out_file = Path(save_csv) if isinstance(save_csv, (str, Path)) else self.output_dir / save_csv
            self.output_dir.mkdir(parents=True, exist_ok=True)
            df.to_csv(out_file, index=False)
            print(f"Aggregated data saved under: {out_file}")

        return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Aggregiert Synthese-Reports zu einem DataFrame.")
    parser.add_argument(
        "--runs",
        type=str,
        default="runs/ingress_sweep.csv",
        help="Pfad zur CSV/TXT-Datei mit den Run-Namen (Standard: runs/ingress_sweep.csv)",
    )
    args = parser.parse_args()

    collector = SynthesisReportCollector()
    
    runs_source = args.runs if Path(args.runs).exists() else [
        "ingress_top_n1_m64_md_1024",
        "ingress_top_n5_m64_md_1024",
    ]

    df = collector.collect_data(
        synth_runs=runs_source,
        instances=[
            ("ingress_top", "Top"),
            ("u_alloc_manager", "Manager"),
            ("u_ingress_crossbar", "Crossbar"),
        ],
        area_datas=["Total-Area", "Cell-Count", "Combinational", "Flop"],
        power_datas=["Leakage", "Internal", "Switching", "Total"],
        include_timing=True,
        save_csv="aggregated_summary.csv",  
    )

    pd.set_option(
        "display.float_format",
        lambda x: f"{x:.3e}" if abs(x) < 0.001 and x != 0 else f"{x:.2f}",
    )
    pd.set_option("display.max_rows", None)
    pd.set_option("display.width", 1000)

    print("\n=== SYNTHESE ERGEBNISSE (TRANSPONIERT) ===")
    print(df.set_index("run_name").T)