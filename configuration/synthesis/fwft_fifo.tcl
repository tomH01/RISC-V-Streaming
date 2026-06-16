#   _____  _____  ____     _
#  |_   _|| ____||  _ \   / \
#    | |  |  _|  | | | | / _ \
#    | |  | |___ | |_| |/ ___ \
#    |_|  |_____||____//_/   \_\
#

set syn_config my

set module "fwft_fifo"

# Get Technology
set technology [EDA::Technology::getTechnology 22fdsoi_plus]
set pdk [$technology getPDK]

$syn_config setTechnology $technology

$syn_config setDesignTopModulePath $module

# Get Metal Stack
$pdk setMetalStack 10M_2Mx_5Cx_1Jx_2Qx_LB 19
#$pdk addConfigVar ENABLE_HV 0

# Standard cells
set stdc_timing_conditions [list \
  TT_0P80V_0P00V_0P00V_0P00V_25C \
  SSG_0P72V_0P00V_0P00V_0P00V_125C \
  SSG_0P72V_0P00V_0P00V_0P00V_M40C \
  FFG_0P88V_0P00V_0P00V_0P00V_125C \
  FFG_0P88V_0P00V_0P00V_0P00V_M40C \
  ]
set stdc [$technology getSTDC "synopsys" gf22nspllogl36edl116f]
$stdc addTimingConditions $stdc_timing_conditions
# set stdc [$technology getSTDC "synopsys" gf22nspllogl36edf116f]
# $stdc addTimingConditions $stdc_timing_conditions


# Parameters
set bottle_dir "/local/hageltom/teda/bottles/risc-v-streaming"
set allowed_params [list \
  DATA_WIDTH \
  DEPTH \
]
source [file normalize [file join $bottle_dir "configuration" "params.tcl"]]
dict for {param value} $::params {
    if {$param in $allowed_params} {
        $syn_config addDesignParameter $param [string cat $value]
    } else {
        puts "\[TEDA-INFO\] Skipping parameter $param (not used in $module)"
    }
}

# Add component
$syn_config addComponent [EDA::Design::getComponent $module] top

# Add Mode
set mode [EDA::Design::createMode mode [list constraints.sdc] [list]]

# Add Corner
set pvt_corner [EDA::Design::createPVTCorner typ [EDA::PVTProcess::TT] 0.8 25 [list TT_0P80V_0P00V_0P00V_0P00V_25C]]

# Add View
set typ_view [EDA::Design::createView typ $mode $pvt_corner [EDA::RCCorner::TYP] [EDA::ViewType::TYPICAL]]

$syn_config addSetupTimeViews [list $typ_view]
$syn_config addHoldTimeViews [list $typ_view]
$syn_config setLeakagePowerView $typ_view
$syn_config setDynamicPowerView $typ_view

# Disable High Effort
$syn_config setHighEffortEnabled 0

# Enable keep hierarchy
$syn_config setPreserveHierarchyEnabled 1

# Change HDL parameter naming style to avoid postsyn errors due to too long parameter names
$syn_config configureElaboration {
  # Use automatic clock gating insertion
  set_db lp_insert_clock_gating true
}

$syn_config configureGeneric {
  # Use scan cells for logic
  set_db use_scan_seqs_for_non_dft degenerated_only

  foreach icg_cell [get_db lib_cells -if {.is_integrated_clock_gating==true}] {
    set_db $icg_cell .dont_use false
  }
}

$syn_config configureOpt {
  # INFO: Workaround for bug (?) in Genus where some clock gating lib cells are dont use after syn_map
  foreach icg_cell [get_db lib_cells -if {.is_integrated_clock_gating==true}] {
    set_db $icg_cell .dont_use false
  }
}
