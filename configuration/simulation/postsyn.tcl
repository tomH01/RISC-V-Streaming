#    _____  _____  ____     _
#   |_   _|| ____||  _ \   / \
#     | |  |  _|  | | | | / _ \
#     | |  | |___ | |_| |/ ___ \
#     |_|  |_____||____//_/   \_\
#
#

set sim_config my

# Set top module paths
$sim_config setDesignTopModulePath "apb_pmc"
$sim_config setSimulationTopModulePath "apb_pmc"

# Add reference to synthesis
set syn_config [EDA::Synthesis::getConfiguration mock_streaming]
$sim_config addReferencedConfiguration $syn_config

# Set timescale
$sim_config setDefaultTimescale "1ps/1ps"

# Add Components
$sim_config addComponent [EDA::Design::getComponent "mock_streaming"] top


#=================
# Setup Simulation
#=================

# Scope to add waveform probe to
$sim_config setWaveformEnabled 1
$sim_config setWaveformType [EDA::WaveformType::SHM]
$sim_config addWaveformScope "apb_pmc"

# Enable cocotb testbenches
$sim_config setPythonTestbenchEnabled 1

#=======
# Timing
#=======
$sim_config addScopeSDFTyp "apb_pmc" [EDA::Synthesis::Files::SDF $syn_config [EDA::Design::getView typ]]
$sim_config setTiming 1
$sim_config setTimingChecks 1
$sim_config setSuppressGlitchCheck 1
$sim_config setSuppressHoldCheck 1
