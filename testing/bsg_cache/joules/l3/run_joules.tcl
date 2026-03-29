#-------------------------------------------------------------------------------
# joules_l3.tcl — Cadence Joules power analysis for L3 Cache (4MB, 16-way, 4096 sets)
#
# Usage:  joules -init joules_l3.tcl
#-------------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [file normalize [info script]]]
source $SCRIPT_DIR/../common_setup.tcl

set design      bsg_cache_l3
set design_name l3
set STIM        $BSG_STL/testing/bsg_cache/power_l3/bsg_cache_l3_pwr.vcd

::legacy::set_attribute information_level 9 /

#-------------------------------------------------------------------------------
# Read libraries
#-------------------------------------------------------------------------------

# MMMC library setup
# Read all libraries in one call
read_libs {*}$STDCELL_LIB_LIST {*}$SRAM_LIB_LIST

# LEF (physical-level estimation)
::legacy::set_attribute lef_library [list \
    $TECH_LEF \
    {*}$STDCELL_LEF_LIST \
    $SRAM_TECH_LEF \
    $SRAM_OVL_LEF \
    {*}$SRAM_LEF_LIST \
]

#-------------------------------------------------------------------------------
# Read RTL
#-------------------------------------------------------------------------------

::legacy::set_attribute hdl_search_path [join $RTL_INCDIRS]

set rtl_files [list \
    {*}$RTL_BSG_MISC \
    {*}$RTL_BSG_MEM \
    {*}$RTL_BSG_MEM_BEHAV \
    {*}$RTL_BSG_DATAFLOW \
    {*}$RTL_BSG_CACHE_CORE \
    $BSG_STL/bsg_cache/bsg_cache.sv \
    $BSG_STL/bsg_cache/bsg_cache_l3.sv \
]

read_hdl -sv $rtl_files

#-------------------------------------------------------------------------------
# Elaborate
#-------------------------------------------------------------------------------

elaborate $design
check_design -unresolved

#-------------------------------------------------------------------------------
# SDC (timing constraints)
#-------------------------------------------------------------------------------

create_clock -name clk -period $CLK_PERIOD [get_ports clk_i]
# All inputs except clock
set_input_delay  [expr $CLK_PERIOD * 0.1] -clock clk [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay [expr $CLK_PERIOD * 0.1] -clock clk [all_outputs]

#-------------------------------------------------------------------------------
# Synthesize
#-------------------------------------------------------------------------------

synthesize -to_generic -effort $SYN_EFF
puts "Runtime & Memory after synthesize -to_generic"
timestat GENERIC

synthesize -to_mapped -effort $MAP_EFF -incr
power_map -effort $MAP_EFF
puts "Runtime & Memory after synthesize -to_mapped"
timestat MAPPED

#-------------------------------------------------------------------------------
# Read stimulus (FSDB)
#-------------------------------------------------------------------------------

read_stimulus -file $STIM \
    -dut_instance testbench/DUT \
    -cycles 1 /clk_i \
    -alias /BASE

#-------------------------------------------------------------------------------
# Compute power
#-------------------------------------------------------------------------------

compute_power -mode $pwra_mode

#-------------------------------------------------------------------------------
# Report
#-------------------------------------------------------------------------------

set d_reports ${joulesWorkDir}/reports
file mkdir $d_reports

set f_rpt $d_reports/${design_name}_power.rpt

report_power -out $f_rpt
report_power -by_hierarchy -levels 3 -out $f_rpt -append
report_activity -by_macro -out $f_rpt -append
report_ppa -out $f_rpt -append

puts "================================================================"
puts " Power report: $f_rpt"
puts "================================================================"

cdn_cat $f_rpt

plot_power_profile \
    -frame {/stim#1/frame#[1:1000]} \
    -by_category memory register logic clock total

puts "joules_l3.tcl completed."
