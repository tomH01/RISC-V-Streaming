set bottle_dir "/local/hageltom/teda/bottles/risc-v-streaming"
set params_file [file join $bottle_dir "configuration" "params.tcl"]

if {![file exists $params_file]} {
    error "Parameter file $params_file does not exist!"
}

puts "Loading parameters from $params_file"
source $params_file

if {![info exists ::params]} {
    error "\$::params is not defined in $params_file"
}

set bd_file [get_files -quiet design_1.bd]

if {$bd_file eq ""} {
    error "Block Design 'design_1.bd' is not registered in current project!"
}

puts "Opening Block Design at: $bd_file"
open_bd_design $bd_file

set target_cell [get_bd_cells -quiet /top_wrapper_0]

if {$target_cell eq ""} {
    error "Could not find BD cell '/top_wrapper_0' in [get_property NAME [current_bd_design]]!"
}

set applied_count 0

dict for {param value} $::params {
    set config_key "CONFIG.${param}"
    
    if {[catch {set_property $config_key $value $target_cell} err]} {
        puts "  -> Skipping parameter '${param}' (Not a generic on $target_cell: $err)"
    } else {
        puts "  -> Applied parameter: ${param} = ${value}"
        incr applied_count
    }
}

if {$applied_count > 0} {
    puts "Successfully updated $applied_count parameters on $target_cell."

    puts "Syncing Bus Interface frequencies to 50 MHz..."
    catch { set_property CONFIG.FREQ_HZ 50000000 [get_bd_intf_pins /top_wrapper_0/s_axi] }
    catch { set_property CONFIG.FREQ_HZ 50000000 [get_bd_intf_pins /top_wrapper_0/s_apb] }
    puts "Assigning address segments..."
    catch {assign_bd_address}

    puts "Validating Block Design..."
    validate_bd_design

    puts "Re-generating BD targets..."
    generate_target all [get_files $bd_file]
    puts "Target generation complete!"
} else {
    puts "Warning: No matching parameters were found to apply to $target_cell."
}