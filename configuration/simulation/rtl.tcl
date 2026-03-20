#    _____  _____  ____     _
#   |_   _|| ____||  _ \   / \
#     | |  |  _|  | | | | / _ \
#     | |  | |___ | |_| |/ ___ \
#     |_|  |_____||____//_/   \_\
#

set sim_config my

set module "ingress_top"

# Set technology
set technology [EDA::Technology::getTechnology "22fdsoi"]
set pdk [$technology getPDK]
$pdk setMetalStack 10M_2Mx_5Cx_1Jx_2Qx_LB 19
$sim_config setTechnology $technology

# Set top module paths
$sim_config setDesignTopModulePath $module
$sim_config setSimulationTopModulePath $module

# Set timescale
$sim_config setDefaultTimescale "1ps/1ps"

# Components
$sim_config addComponent [EDA::Design::getComponent $module] top


$technology getIO "synopsys" dwc_io_gf22fdx_1p8v_gpio_i_ag1
#$technology getSTDC "synopsys" gf22nspllogl36hdl116f
#$technology getSTDC "synopsys" gf22nspllogl36hdf116f
#=================
# Memory components
#=================
$technology getMacro "synopsys" sadclssd4LOW1p128x32m16b1w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p256x32m16b1w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p512x32m16b2w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p1024x32m16b2w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p2048x32m16b2w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p4096x32m16b2w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p8192x32m16b2w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p16384x32m16b4w1c0p1d0l0rm3sdrw01
$technology getMacro "synopsys" sadclssd4LOW1p32768x32m16b8w1c0p1d0l0rm3sdrw01

#=================
# Setup Simulation
#=================

$sim_config setWaveformEnabled 1
$sim_config setWaveformType [EDA::WaveformType::SHM]
$sim_config addWaveformScope $module

# Enable cocotb testbenches
$sim_config setPythonTestbenchEnabled 1

