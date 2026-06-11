#    _____  _____  ____     _
#   |_   _|| ____||  _ \   / \
#     | |  |  _|  | | | | / _ \
#     | |  | |___ | |_| |/ ___ \
#     |_|  |_____||____//_/   \_\
#
#

set sim_config my

if { [EDA::hasTedaEnvironmentParameter MODULE]} {
  set module [EDA::getTedaEnvironmentParameter MODULE]
} else {
  error "MODULE environment parameter not set"
}


# Parameters
set bottle_dir "/local/hageltom/teda/bottles/risc-v-streaming"
source [file normalize [file join $bottle_dir "configuration" "params.tcl"]]
dict for {param value} $::params {
    $sim_config addDesignParameter $param $value
}


# Set top module paths
$sim_config setDesignTopModulePath $module
$sim_config setSimulationTopModulePath $module

# Add reference to synthesis
set syn_config [EDA::Synthesis::getStoredConfiguration $module]
$sim_config addReferencedConfiguration $syn_config

# Set timescale
$sim_config setDefaultTimescale "1ps/1ps"

# Add Components
$sim_config addComponent [EDA::Design::getComponent $module] top


#=================
# Setup Simulation
#=================

# Scope to add waveform probe to
$sim_config setWaveformEnabled 1
$sim_config setWaveformType [EDA::WaveformType::SHM]
$sim_config addWaveformScope $module

# Enable cocotb testbenches
$sim_config setPythonTestbenchEnabled 1

#=======
# Timing
#=======
$sim_config addScopeSDFTyp $module [EDA::Synthesis::Files::SDF $syn_config [EDA::Design::getView typ]]
$sim_config setTiming 1
$sim_config setTimingChecks 1
$sim_config setSuppressGlitchCheck 1
$sim_config setSuppressHoldCheck 1
