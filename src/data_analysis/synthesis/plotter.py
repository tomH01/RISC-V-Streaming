import argparse
import json
from pathlib import Path
from typing import Optional, Union
import matplotlib.pyplot as plt
import pandas as pd

from parse_reports import SynthesisReportCollector

plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.size": 12,
        "axes.labelsize": 13,
        "axes.titlesize": 13,
        "xtick.labelsize": 11,
        "ytick.labelsize": 11,
        "legend.fontsize": 11,
    }
)


class SynthesisReportPlotter:
    COLOR_PALETTE = [
        "#1f77b4",  
        "#ff7f0e",  
        "#2ca02c",  
        "#d62728",  
        "#9467bd",  
        "#8c564b",  
        "#e377c2",  
        "#7f7f7f",  
        "#bcbd22",  
        "#17becf",  
    ]
    OTHER_COLOR = "#555555"
    
    MARGINS = {
        "left": 0.19,
        "right": 0.99,
        "top": 0.98,
        "bottom": 0.12,
    }
    
    FIGSIZE = (4.5, 4.2)
    
    CHAPTER_LABEL = "5_3"

    def _get_colors(self, num_colors: int) -> list[str]:
        return [self.COLOR_PALETTE[i % len(self.COLOR_PALETTE)] for i in range(num_colors)]
    
    def __init__(
        self,
        config_path: Union[str, Path],
        aggregated_df_path: Optional[Union[str, Path]] = None,
        output_dir: Optional[Union[str, Path]] = None,
    ):
        self.collector = SynthesisReportCollector()
        self.config_path = self._resolve_file_path(config_path, search_dir="configs")
        self.config = self._load_config(self.config_path)

        self.stage_name = self.config.get("stage_name", "synthesis_run")
        self.param_label = self.config.get("param_label", "Parameter Value")
        self.area_scale = self.config.get("area_scale_factor", 1.0)
        self.area_unit_label = self.config.get("area_unit_label", r"Area [$\mu\text{m}^2$]")
        self.instances = [tuple(inst) for inst in self.config["instances"]]
        
        if output_dir:
            self.output_dir = Path(output_dir)
        else:
            self.output_dir = (
                self.collector.project_root
                / "output"
                / "plots"
                / "synthesis"
                / self.stage_name
            )

        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.df = self._init_dataframe(aggregated_df_path)

    def _resolve_file_path(
        self, src: Union[str, Path], search_dir: str = "configs"
    ) -> Path:
        src_path = Path(src)
        script_dir = Path(__file__).resolve().parent

        if src_path.exists():
            return src_path

        rel_dir_path = script_dir / search_dir / src_path.name
        if rel_dir_path.exists():
            return rel_dir_path

        script_dir_path = script_dir / src_path.name
        if script_dir_path.exists():
            return script_dir_path

        raise FileNotFoundError(f"Config file not found: {src}")

    def _load_config(self, config_path: Path) -> dict:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)

        required_keys = ["stage_name", "runs", "instances"]
        for key in required_keys:
            if key not in config:
                raise KeyError(
                    f"Missing required key '{key}' in config file {config_path}"
                )

        return config

    def _init_dataframe(self, aggregated_df_path: Optional[Union[str, Path]] = None) -> pd.DataFrame:
        if aggregated_df_path:
            df_path = Path(aggregated_df_path)
            if df_path.exists():
                print(f"Loading precomputed DataFrame from CSV: {df_path}")
                df = pd.read_csv(df_path)
                return df.sort_values("param").reset_index(drop=True)
            else:
                raise FileNotFoundError(
                    f"Passed aggregated DataFrame-CSV not found: {df_path}"
                )

        print(f"Collecting Synthesis-Reports based on JSON: {self.config_path.name}")
        metrics = self.config.get("metrics", {})
        return self.collector.collect_data(
            synth_runs=self.config["runs"],
            instances=self.instances,
            area_datas=metrics.get("area", ["Total-Area"]),
            power_datas=metrics.get("power", ["Leakage", "Internal", "Switching", "Total"]),
            include_timing=metrics.get("include_timing", True),
            save_csv=(self.output_dir / f"aggregated_{self.stage_name}.csv"),
        )

    def _get_area_columns(self):
        area_cols = [c for c in self.df.columns if c.endswith("_Total-Area")]
        top_col = next((c for c in area_cols if any(k in c.lower() for k in ["top", "other"])), None)
        sub_cols = [c for c in area_cols if c != top_col]
        
        return top_col, sub_cols
    
    def plot_area_absolute(self, filename: str = "") -> Path:
        if filename == "":
            filename = f"{self.CHAPTER_LABEL}_{self.stage_name}_area_abs.pdf"
            
        if self.df.empty:
            raise ValueError("DataFrame is empty.")

        fig, ax = plt.subplots(figsize=self.FIGSIZE)
        
        top_col, sub_cols = self._get_area_columns()
        
        if top_col:
            ax.plot(
                self.df["param"],
                self.df[top_col] * self.area_scale,
                "s-",
                color="black",
                linewidth=1.8,
                label="Total",
            )

        colors = self._get_colors(len(sub_cols))
        for idx, col in enumerate(sub_cols):
            alias = col.replace("_Total-Area", "")
            ax.plot(
                self.df["param"],
                self.df[col] * self.area_scale,
                "o--",
                color=colors[idx],
                label=alias,
            )
        
        if top_col and sub_cols:
            sub_sum = self.df[sub_cols].sum(axis=1)
            diff_area = self.df[top_col] - sub_sum
            if (diff_area > 0).any():
                ax.plot(
                    self.df["param"],
                    diff_area * self.area_scale,
                    "o--",
                    color=self.OTHER_COLOR,
                    label="Other",
                )
        
        ax.set_xscale("linear")
        ax.set_yscale("linear")
        ax.set_xlabel(self.param_label)
        ax.set_ylabel(self.area_unit_label)
        ax.grid(True, which="both", linestyle=":", alpha=0.5)
        
        fig.subplots_adjust(**self.MARGINS)
        
        out_path = self.output_dir / filename
        plt.savefig(out_path, dpi=300)
        plt.close()

        print(f"Plot saved: {out_path}")
        return out_path

    def plot_area_relative(self, filename: str = "") -> Path:
        if filename == "":
            filename = f"{self.CHAPTER_LABEL}_{self.stage_name}_area_rel.pdf"
            
        if self.df.empty:
            raise ValueError("DataFrame is empty.")

        fig, ax = plt.subplots(figsize=self.FIGSIZE)

        top_col, sub_cols = self._get_area_columns()
        
        
        x_labels = [str(int(p)) for p in self.df["param"]]
        bottom_stack = pd.Series([0.0] * len(self.df))
        colors = self._get_colors(len(sub_cols))
        ref_total = self.df[top_col] if top_col else self.df[sub_cols].sum(axis=1)
        
        for idx, col in enumerate(sub_cols):
            alias = col.replace("_Total-Area", "")
            pct = (self.df[col] / ref_total) * 100
            ax.bar(
                x_labels,
                pct,
                bottom=bottom_stack,
                label=alias,
                color=colors[idx],
            )
            bottom_stack += pct
            
        if top_col:
            other_pct = 100.0 - bottom_stack
            if (other_pct > 1.0).any():
                ax.bar(
                    x_labels,
                    other_pct,
                    bottom=bottom_stack,
                    label="Other",
                    color=self.OTHER_COLOR,
                )
        
        ax.set_xlabel(self.param_label)
        ax.set_ylabel("Area Share [%]")
        ax.set_ylim(0, 100)
        ax.grid(True, axis="y", linestyle=":", alpha=0.5)

        fig.subplots_adjust(**self.MARGINS)
        
        out_path = self.output_dir / filename
        plt.savefig(out_path, dpi=300)
        plt.close()

        print(f"Plot saved: {out_path}")
        return out_path

    def plot_power(self, filename: str = "") -> Path:
        if filename == "":
            filename = f"{self.CHAPTER_LABEL}_{self.stage_name}_power.pdf"
        
        if self.df.empty:
            raise ValueError("DataFrame is empty.")

        fig, ax = plt.subplots(figsize=self.FIGSIZE)

        if "Top_Total" in self.df.columns:
            ax.plot(
                self.df["param"],
                self.df["Top_Total"] * 1e3,
                "o-",
                color="black",
                label="Total Power",
            )
        if "Top_Switching" in self.df.columns:
            ax.plot(
                self.df["param"],
                self.df["Top_Switching"] * 1e3,
                "s--",
                color="#e7298a",
                label="Switching",
            )
        if "Top_Internal" in self.df.columns:
            ax.plot(
                self.df["param"],
                self.df["Top_Internal"] * 1e3,
                "^--",
                color="#66a61e",
                label="Internal",
            )
        if "Top_Leakage" in self.df.columns:
            ax.plot(
                self.df["param"],
                self.df["Top_Leakage"] * 1e3,
                "x:",
                color="#e6ab02",
                label="Leakage",
            )

        ax.set_xlabel(self.param_label)
        ax.set_ylabel("Power [mW]")
        ax.grid(True, linestyle=":", alpha=0.5)
        ax.legend()

        fig.subplots_adjust(**self.MARGINS)
        out_path = self.output_dir / filename
        plt.savefig(out_path, dpi=300)
        plt.close()

        print(f"Plot saved: {out_path}")
        return out_path

    def plot_timing(self, filename: str = "") -> Path:
        if filename == "":
            filename = f"{self.CHAPTER_LABEL}_{self.stage_name}_timing.pdf"
            
        if self.df.empty:
            raise ValueError("DataFrame is empty.")

        fig, ax = plt.subplots(figsize=self.FIGSIZE)

        if "Timing_DataPath_ps" in self.df.columns:
            ax.plot(
                self.df["param"],
                self.df["Timing_DataPath_ps"],
                "d-",
                color="#e41a1c",
                label="Critical Path Delay",
            )
            if "Timing_ReqTime_ps" in self.df.columns:
                req_time = self.df["Timing_ReqTime_ps"].iloc[-1]
                ax.axhline(
                    y=req_time,
                    color="black",
                    linestyle="--",
                    label=f"Required Time ({req_time/1000:.2f} ns)",
                )

            ax.set_xlabel(self.param_label)
            ax.set_ylabel("Delay [ps]")
            ax.grid(True, linestyle=":", alpha=0.5)
            ax.legend()

        fig.subplots_adjust(**self.MARGINS)
        out_path = self.output_dir / filename
        plt.savefig(out_path, dpi=300)
        plt.close()

        print(f"Plot saved: {out_path}")
        return out_path

    def plot_all(self):
        self.plot_area_absolute()
        self.plot_area_relative()
        self.plot_power()
        self.plot_timing()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generic plot-tool for Synthesis Reports."
    )
    parser.add_argument(
        "--cfg",
        type=str,
        default="ingress.json",
        help="Path to the JSON configuration file for the synthesis runs.",
    )
    parser.add_argument(
        "--df",
        type=str,
        default=None,
        help="Optional: Path to a pre-aggregated Summary-CSV",
    )
    parser.add_argument(
        "--out",
        type=str,
        default=None,
        help="Optional: Target directory for PDF-Plots",
    )
    args = parser.parse_args()

    plotter = SynthesisReportPlotter(
        config_path=args.cfg,
        aggregated_df_path=args.df,
        output_dir=args.out,
    )
    plotter.plot_all()
    