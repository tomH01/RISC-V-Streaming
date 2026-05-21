import os


def get_param(dut, name):
    if hasattr(dut, name):
        return int(getattr(dut, name).value)
    teda_str = os.environ.get("TEDA_PARAMS", "")
    params = dict(param.split("=") for param in teda_str.split(":") if "=" in param)
    return int(params[name])