#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#
set power_config my


set sim_config [EDA::Simulation::getConfiguration "postsyn"]
set syn_config [EDA::Synthesis::getConfiguration "mock_streaming"]

set use_sim_report_timeframe 0
if {[EDA::hasParameter USE_SIM_REPORT_TIMEFRAME]} {
  set use_sim_report_timeframe [EDA::getParameter USE_SIM_REPORT_TIMEFRAME]
}

$power_config addReferencedConfiguration $sim_config
$power_config addReferencedConfiguration $syn_config

$power_config addViews [$syn_config getSetupTimeViews]

$power_config setTimeBasedModeEnabled 0
$power_config setParasiticsEnabled 1

# Set simulation time frames with values from simulation results file
# if ($use_sim_report_timeframe) {
#     package require fileutil
#     package require yaml
#     set bottle_home [EDA::getEnv TEDA_BOTTLE_HOME]
#     set report_file_path "${bottle_home}/output/simulation/postsyn/reports/report.yml"
#     if ([file exist $report_file_path]) {
#         puts "Use timeframe from simulation report file: $report_file_path"
#         set report [yaml::yaml2dict -file $report_file_path]
#         set program_start [lindex [regexp -inline {(\d+)ns} [dict get $report program_start]] 1]
#         set program_end [lindex [regexp -inline {(\d+)ns} [dict get $report program_end]] 1]
#         puts "start=${program_start}ns end=${program_end}ns"
#         $power_config setPowerWaveformTimeFrames $sim_config [list $program_start $program_end]
#     } else {
#         puts "Simulation report file does not exist: $report_file_path"
#         exit 1
#     }
# }

# Add simulation trace
$power_config setTimeResolution ns
$power_config addPowerWaveformScope $sim_config "apb_pmc" "apb_pmc"
