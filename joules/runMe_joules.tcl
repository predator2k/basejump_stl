#-------------------------------------------------------------------------------
# Configurable parameters
#-------------------------------------------------------------------------------

set demo 0 ; set run_cpf 1 ; 
# set run_dft [string equal [exec domainname] "cadence.com"]
set run_dft 0 ;# 1 | 0 -> run DFT flow
set gen_sdb 1 ; set ungroup 0 ; set rtlstim2gate 0
set use_wlm 0 ; set use_ple 1 ; set tune_ple 0
set pwra_mode "time_based" ;# average| time_based
set voltus_compare 0 ;# run voltus_compare to compare Joules vs Voltus power
set read_stim "after_synth" ;# after_elab | after_synth
set use_stim vcd ; # vcd | fsdb
set use_multi_host 0 ;# 0 | 1 -> read_stimulus using multi_host_read on fsdb



if {${use_stim} != "fsdb" && ${use_multi_host} } {
    error "Error: only FSDB Stim file can be used for parallel Stimulus reading... 
    Please set use_stim fsdb , and run the script again"
}
set design active_cta_table ;# design name
set vcd1 active_cta_table.vcd
#set vcd2 ${design}_pgm_gcf.vcd
#set fsdb1 ${design}_pgm_hash.fsdb
#set fsdb2 ${design}_pgm_gcf.fsdb
set sdb  ${design}.sdb
#
set has_cpf [expr ![string compare $design "active_cta_table"]] ;# cpu_10bit has CPF
set use_cpf [expr $run_cpf && $has_cpf]

set d_work /data/jwang710/dice-rtl/pwr
set d_rtl  /data/jwang710/dice-rtl
switch $use_stim {
    vcd {
        set STIM1 $d_rtl/tb/cgra_core/CS_stage/${design}/$vcd1
        # set STIM2 $d_tutorial/stimulus/$vcd2
    }
    fsdb {
        set STIM1 $d_tutorial/stimulus/$fsdb1
        set STIM2 $d_tutorial/stimulus/$fsdb2
    }
    default {
        set STIM1 $d_tutorial/stimulus/$vcd1
        set STIM2 $d_tutorial/stimulus/$vcd2
    }
}
set SDB  joules_work/$sdb
set SDC  $d_work/chip.sdc
set CPF  $d_work/cgra_core/active_cta_table/chip.cpf

set bname ${design}
if { [is_novus_ui_mode] } { append bname ".novus" }
#
set f_rpt ${bname}.rpt
set f_elab_db ${bname}.elab.db
set f_proto_db ${bname}.non_dft.proto.db
set f_netlist ${bname}.netlist.v
set f_proto_dft_db ${bname}.proto.db
set f_netlist_dft ${bname}.netlist.dft.v

set SYN_EFF medium
set MAP_EFF medium ;# low|medium|high

set today  [cdn_get_date]
#
set d_outputs $joulesWorkDir/outputs/$today
set d_reports $joulesWorkDir/reports/$today
set d_logs    $joulesWorkDir/logs/$today
foreach _dir "logs reports outputs" {
    if { [file exists $joulesWorkDir/$_dir] } continue;
    file mkdir $joulesWorkDir/$_dir
}

::legacy::set_attribute information_level 9 /

# applet: timing and slack histograms
applet load report_histogram
# applet load report_timing_histogram

#-------------------------------------------------------------------------------
# Utility procs
#-------------------------------------------------------------------------------

# proc load_stim { STIM1 STIM2 } {
proc load_stim { STIM1 } {
    upvar design    design
    upvar pwra_mode pwra_mode

    set read_stim_timebased_opt [set read_stim_timebased_opt2 ""]
    if { $pwra_mode == "time_based" } {
        set read_stim_timebased_opt  "-cycles 1 /${design}/clk"
        #set read_stim_timebased_opt2 "-cycles 5 /${design}/clk"
    }
    eval read_stimulus -file $STIM1 -dut_instance tb_${design}/dut \
        $read_stim_timebased_opt -alias /BASE ;# -compat voltus
    #eval read_stimulus -file $STIM2 -dut_instance /${design}_tb/CPU \
    #    $read_stim_timebased_opt2 -alias /TestGCF -append ;# -compat voltus

    return 0
}

#proc load_stim_multi_host { STIM1 STIM2 } {
proc load_stim_multi_host { STIM1 } {
    upvar design    design
    upvar pwra_mode pwra_mode

    set read_stim_timebased_opt [set read_stim_timebased_opt2 ""]
    if { $pwra_mode == "time_based" } {
        set read_stim_timebased_opt  "-cycles 1 /${design}/clk"
        #set read_stim_timebased_opt2 "-cycles 5 /${design}/clk"
    }
    eval read_stimulus -file $STIM1 -dut_instance tb_${design}/dut \
        $read_stim_timebased_opt -alias /BASE \
	-multi_host_read -shut_down_servers ;# -compat voltus
    #eval read_stimulus -file $STIM2 -dut_instance /${design}_tb/CPU \
    #    $read_stim_timebased_opt2 -alias /TestGCF -append \
	#-multi_host_read -shut_down_servers ;# -compat voltus

    return 0
}

#-------------------------------------------------------------------------------
# Read Library and Create Library Domains
#-------------------------------------------------------------------------------

#set d_lib $d_tutorial/libraries
#::legacy::set_attribute lib_search_path ". $d_lib/LIB $d_lib/LEF"
read_mmmc $d_work/freepdk45_mmmc.tcl
# if { $use_cpf } {
#     #
#     # CPF Flow
#     # Create library domains used in CPF define_library_set commands
#     # See tutorial CPF file: $RTLS_REGLIBS/tutorial/cpu_10bit/cpu.cpf
#     # define_library_set -name lib_1p08v -libraries $Lib_1p08v_list
#     # define_library_set -name lib_1p20v -libraries $Lib_1p20v_list
#     #
#     set Lib_1p08v_list "slow.lib pwr_mgmt.lib" ;# 1.08v libs
#     set Lib_1p20v_list "typical.lib CDK_S64x10.lib" ;# 1.20v libs
#     read_libs -domain lib_1p08v -flist $d_lib/LIB/libs_1p08v.txt -node node_tutorial
#     read_libs -domain lib_1p20v -libs $Lib_1p20v_list -node node_tutorial
# 
# } else {
#     #
#     # Non CPF flow
#     # No need for library domains
#     #
#     read_libs typical.lib CDK_S64x10.lib -node node_tutorial
# }

# LEF and Captable
if { $use_ple } {
    ::legacy::set_attribute lef_library \
        { /data/eda_tools/pdk/freepdk-45nm/rtk-tech.lef \ 
        /data/eda_tools/pdk/freepdk-45nm/stdcells.lef}
    ::legacy::set_attribute cap_table_file \
        /data/eda_tools/pdk/freepdk-45nm/rtk-typical.captable
}

# tag_memory CDK_S64x10 \
#     -addr ADDR* -din DATA_IN -clock CLOCK \
#     -dout DATA_OUT \
#     -wr_enable WR_EN* -mem_enable ENABLE \
#     -wr_cycles 2 -depth 64 -width 10

# ::legacy::set_attribute wireload_mode <value> /
# ::legacy::set_attribute force_wireload <wireload name> "/$design"

if { $demo && ! [cdn_pause "<read_libs done> Continue? "] } { return -1 }

#-------------------------------------------------------------------------------
# Read Design and Power Intent
#-------------------------------------------------------------------------------

if { $rtlstim2gate } {
    ::legacy::set_attribute -quiet ungroup_separator "__SLASH__" /
    ::legacy::set_attribute -quiet hdl_reg_naming_style "%s__REGISTER%s" /
  # ::legacy::set_attribute -quiet hdl_array_naming_style "%s_%d" /
    ::legacy::set_attribute -quiet hdl_generate_separator "__GEN__" /
}

# track filename/line number through the flow
# ::legacy::set_attribute hdl_track_filename_row_col 1 /

::legacy::set_attribute hdl_search_path $d_rtl/cgra_core/cta_schedule

read_hdl \
active_cta_table.sv \
-language sv

if { $use_cpf } {
    catch { read_power_intent -cpf $CPF -module $design }
    if { $demo && ! [cdn_pause "<read_power_intent done> Continue? "] } { return -1 }
}

elaborate $design
check_design -unresolved

# preserve RTL hierarchy - following is forced in Joules (do not uncomment)
# set alu_subd [::legacy::get_attribute subdesign /$design/DP/ALU]
# if { [get_attribute_status allow_csa_subdesign -type subdesign] } {
#     ::legacy::set_attribute allow_csa_subdesign false $alu_subd
# } else {
#     ::legacy::set_attribute dp_csa none $alu_subd
# }
# ::legacy::set_attribute allow_sharing_subdesign false $alu_subd
# ::legacy::set_attribute dp_csa     <val> $alu_subd ;# old attribute: allow_csa_subdesign 
# ::legacy::set_attribute dp_sharing <val> $alu_subd ;# old attribute: allow_sharing_subdesign

# Read and commit CPF
if { $use_cpf } {
    catch { apply_power_intent ; commit_power_intent }
    if { $demo && ! [cdn_pause "<apply/commit_power_intent done> Continue? "]   } { return -1 }
}

# save elab DB
write_db -all -to_file $f_elab_db

if { $demo && ! [cdn_pause "<elaborate done> Continue? "] } { return -1 }

#-------------------------------------------------------------------------------
# Read stimulus, generate SDB
#-------------------------------------------------------------------------------

if { $gen_sdb || ($read_stim == "after_elab") } {
    if {$use_multi_host} {
        echo "Setting up multi_host_read settings ..."
        ::legacy::set_attribute super_thread_servers {localhost}
        ::legacy::set_attribute super_thread_debug_directory ${joulesWorkDir}/mth_st_log_dir
        ::legacy::set_attribute max_cpus_per_server 8
        echo "Done setting up multi_host_read settings ..."
        #load_stim_multi_host $STIM1 $STIM2
        load_stim_multi_host $STIM1
    } else {
        #load_stim $STIM1 $STIM2
        load_stim $STIM1 
    }
    if { $gen_sdb } { write_sdb -out $SDB }
    if { $demo && ! [cdn_pause "<read_stimulus done> Continue? "] } { return -1 }
}

#-------------------------------------------------------------------------------
# Read SDC
#-------------------------------------------------------------------------------

read_sdc $SDC

# define cost groups: C2C, C2O, I2C, I2O. Also available 2M (to_mem), FM (from_mem)
set cgroups "C2C C2O I2C I2O"
set_joules_cost_groups -cost_groups $cgroups
report timing -cost_group $cgroups >> $d_reports/${design}_pretim.rpt

report timing -lint
puts "Number of exceptions: [llength [vfind /$design -exception *]]"
if { $demo && ! [cdn_pause "<read_sdc done> Continue? "] } { return -1 }

#-------------------------------------------------------------------------------
# RUN SETUP
#-------------------------------------------------------------------------------

# JRoy 2016.01.13: ungroup /cpu_10bit/FSM to test rtlstim2gate
# if { $ungroup && (! $run_cpf) } {
#     set fsm_subd [vfind / -subdesign *__fsm]
#     ::legacy::set_attribute -quiet ungroup_ok true $fsm_subd
#     ::legacy::set_attribute -quiet logical_hier false $fsm_subd
#     ::legacy::set_attribute ui_respects_preserve false /
#     ungroup /cpu_10bit/FSM
# }

if { $use_wlm && ([::legacy::get_attribute interconnect_mode /] eq "wireload") } {
    ::legacy::set_attribute force_wireload small_wlm /$design ;# zero_wlm|small_wlm|medium_wlm|large_wlm
    # ::legacy::set_attribute wireload_mode <value> /
    # ::legacy::set_attribute force_wireload <wireload name> "/$design"
}

# Turn on TNS, affects global and incr opto (doesn't do much w/ global map)
::legacy::set_attribute tns_opto true /

::legacy::set_attribute lp_insert_clock_gating true /
::legacy::set_attribute lp_clock_gating_min_flops  2 /$design
::legacy::set_attribute lp_clock_gating_max_flops  6 /$design ;# try 6|9|12|18

# ::legacy::set_attribute lp_clock_gating_prefix <string> /
# ::legacy::set_attribute power_optimization_effort medium / ;# low|medium|high
# ::legacy::set_attribute lp_power_analysis_effort <high> /
# ::legacy::set_attribute lp_power_unit mW /
# ::legacy::set_attribute lp_toggle_rate_unit /ns /

# ::legacy::set_attribute lp_clock_gating_cell \
#     [vfind /lib* -libcell <iccg_libcell>] "/$design"
# ::legacy::set_attribute max_leakage_power 0.0 "/$design"
# ::legacy::set_attribute lp_power_optimization_weight <value from 0 to 1> "/$design"
# ::legacy::set_attribute max_dynamic_power <number> "/$design"
# ::legacy::set_attribute lp_clock_gating_test_signal <test_signal_object> "/$design"

# turn off sequential merging
::legacy::set_attribute optimize_merge_flops false /
::legacy::set_attribute optimize_merge_latches false /

# setup for DFT
#source $d_tutorial/dft/dft_setup.tcl ;# setup for DFT
::legacy::set_attribute ui_respects_preserve false /

#-------------------------------------------------------------------------------
# Synthesize to Generic Gates
#-------------------------------------------------------------------------------

puts stdout "synthesize -to_generic -effort $SYN_EFF"
synthesize -to_generic -effort $SYN_EFF
puts "Runtime & Memory after 'synthesize -to_generic'"
timestat GENERIC

plot_slack_profile -resolution 10
if { $demo } {
    if { ! [cdn_pause "<synthesize -to_generic> Continue? "] } { return 0 }
} else {
    report_slack_histogram -slack_limit 0
}

# Build RTL power models
# build_rtl_power_models -design $design -clean_up_netlist \
#     [-clock_gating_logic] [-relative <hierarchical instance>]
# report power -rtl

#-------------------------------------------------------------------------------
# Synthesizing to Gates
#-------------------------------------------------------------------------------

# Add '-auto_identify_shift_registers' to 'synthesize -to_map' to automatically 
# identify functional shift register segments.

# ::legacy::set_attribute dump_stack_trace 10 /
synthesize -to_mapped -effort $MAP_EFF -incr
power_map -effort $MAP_EFF
write_db -all -to_file $joulesWorkDir/$f_proto_db
write_design [get_root]

if { 0 } {

foreach cg [vfind / -cost_group *] {
    set bname [basename $cg]
    set f_rpt $d_reports/${design}_${bname}_post_map.rpt
    report timing -cost_group [list $cg] > $f_rpt
}

# Intermediate netlist for LEC verification
write_hdl -lec > $d_outputs/${design}_intermediate.v
write_do_lec -revised_design $d_outputs/${design}_intermediate.v -logfile $d_logs/rtl2intermediate.lec.log > $d_outputs/rtl2intermediate.lec.do

}

report_slack_histogram -slack_limit 0
if { $demo && ! [cdn_pause "<synthesize -to_mapped done> Continue? "] } {
    return 0
}

#-------------------------------------------------------------------------------
# Save proto DB + netlist
#-------------------------------------------------------------------------------

write_db -all -to_file $f_proto_db
puts stdout "Joules Proto DB: $f_proto_db"

write_hdl > $f_netlist
puts stdout "Joules Netlist (non DFT): $f_netlist"

if { $demo && ! [cdn_pause "<write_db done> Continue? "] } {
    return 0
}

#-------------------------------------------------------------------------------
# Insert DFT
#-------------------------------------------------------------------------------

if { $run_dft } {
    set d_tutorial $env(RTLS_REGLIBS)/tutorial
    set d_lib $d_tutorial/libraries

    source $d_tutorial/dft/dft_scan.tcl
    synthesize -to_mapped -effort $MAP_EFF -incr
    source $d_tutorial/dft/dft_report.tcl

    # Write default flow for ET ATPG analysis
    write_et_atpg -directory ./et_work -library $d_lib/atpg/stdcell.v \
        -ncsim_library "$d_lib/verilog/include_libraries_sim.v"
    # exec et -e ./et_work/runet.atpg ;# run ATPG and report scan coverage
    # exec ./et_work/run_fullscan_sim ;# validate patterns in ncverilog (optional)

    write_db -all -to_file $f_proto_dft_db
    puts stdout "Joules Proto DB w/ DFT: $f_proto_dft_db"

    write_hdl > $f_netlist_dft
    puts stdout "Joules DFT Netlist: $f_netlist_dft"
}

#-------------------------------------------------------------------------------
# Clock Tree
#-------------------------------------------------------------------------------

if { $demo && ! [cdn_pause "do gen_clock_tree? "] } { return 0 }

# set root_fanout 4 ; set branch_fanout 4 ; set leaf_fanout 6
set root_fanout 3 ; set branch_fanout 3 ; set leaf_fanout 4
set root_buffers "CLKBUF_X2" ; set branch_buffers "CLKBUF_X2"
set leaf_buffers "CLKBUF_X2 CLKBUF_X3"
gen_clock_tree -name CT1 \
    -fanout root=$root_fanout branch=$branch_fanout leaf=$leaf_fanout \
    -root_buffers $root_buffers -branch_buffers $branch_buffers -leaf_buffers $leaf_buffers \
    -max_tree_depth 5

#-------------------------------------------------------------------------------
# Power Analysis
#-------------------------------------------------------------------------------

if { $read_stim == "after_synth" } {
    # load SDB
    read_stimulus -file $SDB
    if { $demo && ! [cdn_pause "<read_stimulus done> Continue? "] } { return 0 }
}

if { $tune_ple && ([::legacy::get_attribute interconnect_mode /] eq "ple") } {
    tune_ple_from_spef \
        -f_spef /home/jroy/Work/ExampleFiles/Xm_s37Xttop_netlist.spef.gz \
        -debug
      # -refine_net_cap memory clock
}

# propagate_activity
compute_power -mode $pwra_mode
if { $demo && ! [cdn_pause "<compute_power done> Continue? "] } { return 0 }

#-------------------------------------------------------------------------------
# Report
#-------------------------------------------------------------------------------

if { $demo && ! [cdn_pause "<begin reporting> Continue? "] } { return 0 }

report_activity -by_macro -out $f_rpt
if { $demo && ! [cdn_pause "<report_activity done> Continue? "] } { return 0 }

report_ppa      -out $f_rpt -append ;# requires compute_power
if { $demo && ! [cdn_pause "<report_ppa done> Continue? "] } { return 0 }

report_power -out $f_rpt -append
# report_power -stim /stim#1 -out $f_rpt -append
# report_power -stim /stim#2 -out $f_rpt -append
plot_power_profile -frame {/stim#1/frame#[1:1000]} -by_category memory register logic clock total
plot_power_profile -frame {/stim#1/frame#[1:1000]} -types leakage internal switching dynamic total
if { $demo && ! [cdn_pause "<report_power done> Continue? "] } { return 0 }
report_icgc_efficiency -out $f_rpt -append
#
cdn_cat $f_rpt

#-------------------------------------------------------------------------------
# voltus_compare
#-------------------------------------------------------------------------------

# if { $voltus_compare } {
#     foreach stim_id [get_sdb_stims] {
#         set f_stim [get_stim_info $stim_id -src_file]
#         set bname [lindex [split [file tail $f_stim] "."] 0]
#         voltus_compare -stimulus $stim_id -bname $bname -generate script -add_power
#         voltus_compare -stimulus $stim_id -bname $bname -generate data -pin_dir out -add_power
#         if { $demo } {
#             if { ! [cdn_pause "<Run shell command: voltus -init voltus_work/${bname}_run_voltus.tcl> Continue? "] } { continue }
#             voltus_compare -bname $bname -plot all -add_power
#         } else {
#             puts stdout "<Run shell command: voltus -init voltus_work/${bname}_run_voltus.tcl>"
#             voltus_compare -bname $bname -compute_stats
#         }
#     }
# }

#-------------------------------------------------------------------------------
# Done
#-------------------------------------------------------------------------------

puts stdout "runMe_joules.tcl completed."

